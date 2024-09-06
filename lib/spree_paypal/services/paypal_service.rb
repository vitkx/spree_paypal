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
        intent: 'CAPTURE',
        purchase_units: purchase_units
      }.to_json

      response = send_request(uri, request)
      JSON.parse(response.body)
    end

    def capture_order(order_id)
      auth_token = authenticate
      
      uri = URI.parse("#{@api_base_url}/v2/checkout/orders/#{order_id}/capture")
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{auth_token}"
      request["Content-Type"] = "application/json"

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
      discount_total = order.promo_total.abs.to_s
      tax_total = order.additional_tax_total.to_s
      shipping_total = order.shipment_total.to_s

      items = order.line_items.map do |line_item|
        {
          name: line_item.product.name,
          quantity: line_item.quantity.to_s,
          unit_amount: {
            currency_code: order.currency || 'USD',
            value: line_item.price.to_s
          }
        }
      end

      [{
        reference_id: order.id,
        amount: {
          currency_code: order.currency || 'USD',
          value: order.total.to_s,
          breakdown: {
            item_total: {
              currency_code: order.currency || 'USD',
              value: order.item_total.to_s
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