require 'net/http'
require 'uri'
require 'json'
require 'base64'

module SpreePaypal
  class PaypalService
    SANDBOX_API_URL = "https://api.sandbox.paypal.com"
    LIVE_API_URL = "https://api.paypal.com"

    def initialize(payment_method)
      @client_id = payment_method.preferred_client_id
      @client_secret = payment_method.preferred_client_secret
      @api_base_url = payment_method.sandbox? ? SANDBOX_API_URL : LIVE_API_URL
    end

    def create_order(order)
      auth_token = authenticate
      purchase_units = build_purchase_units(order)
      uri = URI.parse("#{@api_base_url}/v2/checkout/orders")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{auth_token}"
      request["Content-Type"] = "application/json"
      request.body = {
        intent: 'AUTHORIZE',
        purchase_units: purchase_units
      }.to_json

      response = send_request(uri, request)
      JSON.parse(response.body)
    end

    def authorize_order(order_id)
      auth_token = authenticate
      
      uri = URI.parse("#{@api_base_url}/v2/checkout/orders/#{order_id}/authorize")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{auth_token}"
      request["Content-Type"] = "application/json"

      response = send_request(uri, request)
      JSON.parse(response.body)
    end

    def capture_authorized_payment(authorization_id, amount, currency)
      auth_token = authenticate

      uri = URI.parse("#{@api_base_url}/v2/payments/authorizations/#{authorization_id}/capture")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{auth_token}"
      request["Content-Type"] = "application/json"

      request.body = {
        amount: {
          value: amount.to_s,
          currency_code: currency
        },
        final_capture: true
      }.to_json

      response = send_request(uri, request)
      JSON.parse(response.body)
    end

    def void_authorization(authorization_id)
      auth_token = authenticate

      uri = URI.parse("#{@api_base_url}/v2/payments/authorizations/#{authorization_id}/void")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{auth_token}"
      request["Content-Type"] = "application/json"

      response = send_request(uri, request)
      # PayPal returns 204 No Content on a successful void; body is empty.
      return {} if response.code.to_i == 204

      JSON.parse(response.body)
    rescue JSON::ParserError
      {}
    end

    def reauthorize_authorization(authorization_id, amount, currency)
      auth_token = authenticate

      uri = URI.parse("#{@api_base_url}/v2/payments/authorizations/#{authorization_id}/reauthorize")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{auth_token}"
      request["Content-Type"] = "application/json"

      request.body = {
        amount: {
          value: amount.to_s,
          currency_code: currency
        }
      }.to_json

      response = send_request(uri, request)
      JSON.parse(response.body)
    end

    def void_and_authorize(authorization_id, order)
      void_response = void_authorization(authorization_id)
      if void_response['name'] == 'RESOURCE_NOT_FOUND'
        return ActiveMerchant::Billing::Response.new(false, 'The specified PayPal resource does not exist', void_response)
      end
      create_order_response = create_order(order)
      if create_order_response['status'] != 'CREATED'
        return ActiveMerchant::Billing::Response.new(false, 'Failed to create new PayPal order for reauthorization', create_order_response)
      end
      new_order_id = create_order_response['id']
      new_authorize_response = authorize_order(new_order_id)
      if new_authorize_response['status'] != 'COMPLETED'
        return ActiveMerchant::Billing::Response.new(false, 'Failed to authorize new PayPal order for reauthorization', new_authorize_response)
      end
      new_authorization_id = new_authorize_response['purchase_units'][0]['payments']['authorizations'][0]['id']
      ActiveMerchant::Billing::Response.new(true, 'PayPal payment reauthorized', new_authorize_response.merge('authorization_id' => new_authorization_id))
      new_authorization_id
    end

    def refund_by_capture_id(capture_id, amount, originator)
      auth_token = authenticate

      uri = URI.parse("#{@api_base_url}/v2/payments/captures/#{capture_id}/refund")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{auth_token}"
      request["Content-Type"] = "application/json"

      request.body = {
        amount: {
          value: amount.to_s('F'),
          currency_code: originator.order.currency
        }
      }.to_json

      response = send_request(uri, request)
      JSON.parse(response.body)
    end

    def add_tracking(transaction_id, tracking_number, carrier, status = "SHIPPED")
      auth_token = authenticate
  
      uri = URI.parse("#{@api_base_url}/v1/shipping/trackers-batch")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{auth_token}"
      request["Content-Type"] = "application/json"

      request.body = {
        trackers: [
          {
            transaction_id: transaction_id,
            tracking_number: tracking_number,
            status: status,
            carrier: carrier
          }
        ]
      }.to_json

      response = send_request(uri, request)
      JSON.parse(response.body)
    end

    private

    def authenticate
      uri = URI.parse("#{@api_base_url}/v1/oauth2/token")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Basic #{Base64.strict_encode64("#{@client_id}:#{@client_secret}")}"
      request["Content-Type"] = "application/x-www-form-urlencoded"
      request.body = URI.encode_www_form(grant_type: 'client_credentials')

      response = send_request(uri, request)
      JSON.parse(response.body)['access_token']
    end

    def build_purchase_units(order)
      if order.shipments.pending.any? {|a| a.replacement}
        discount_total = 0.to_s
        tax_total = order.additional_tax_total.to_s
        shipping_total = 0
        item_total = 0

        order.shipments.pending.map do |shipment|
          next if shipment.free_replacement?

          shipping_total += shipment.cost
          
          items = shipment.manifest.map do |manifest_item|
            line_item = manifest_item.first
            quantity = manifest_item.states["on_hand"]
            item_total += line_item.price * quantity
            {
              name: line_item.product.name,
              quantity: quantity.to_s,
              sku: line_item.variant&.sku.to_s[0, 127],
              unit_amount: {
                currency_code: order.currency || 'USD',
                value: line_item.price.to_s
              }
            }
          end
        end

        shipping_total = shipping_total.to_s
        item_total = item_total.to_s
      else
        discount_total = order.promo_total.abs.to_s
        tax_total = order.additional_tax_total.to_s
        shipping_total = order.shipment_total.to_s
        item_total = order.line_items.sum { |li| li.price * li.quantity }.to_s

        items = order.line_items.map do |line_item|
          {
            name: line_item.product.name,
            quantity: line_item.quantity.to_s,
            sku: line_item.variant&.sku.to_s[0, 127],
            unit_amount: {
              currency_code: order.currency || 'USD',
              value: line_item.price.to_s
            }
          }
        end
      end

      [{
        reference_id: order.id,
        amount: {
          currency_code: order.currency || 'USD',
          value: order.outstanding_balance.to_s,
          breakdown: {
            item_total: {
              currency_code: order.currency || 'USD',
              value: item_total
            },
            discount: {
              currency_code: order.currency || 'USD',
              value: discount_total
            },
            shipping: {
              currency_code: order.currency || 'USD',
              value: shipping_total
            },
            tax_total: {
              currency_code: order.currency || 'USD',
              value: tax_total
            },
          }
        },
        items: items
      }]
    end

    def send_request(uri, request)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.request(request)
    end
  end
end
