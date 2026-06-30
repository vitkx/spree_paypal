module Spree
  class PaypalController < Spree::StoreController
    protect_from_forgery with: :null_session

    def create_order
      if params[:order_id]
        order = Spree::Order.find(params[:order_id])
      else
        order = current_order
      end
      payment_method = Spree::PaymentMethod.find(params[:payment_method_id])

      service = SpreePaypal::PaypalService.new(payment_method)
      response = service.create_order(order)

      if response['id']
        render json: { orderID: response['id'] }, status: :ok
      else
        render json: { error: response['message'] }, status: :unprocessable_entity
      end
    end

    def authorize_order
      if params[:order]&.[](:email)&.empty?
        render json: { error: 'Email is required' }, status: :unprocessable_entity
        return
      end

      if params[:order]&.[](:bill_address_attributes).present?
        check_required_fields = %w[firstname lastname address1 city state_id zipcode country_id]
        if params[:order][:bill_address_attributes].values_at(*check_required_fields).any?(&:blank?)
          render json: { error: 'All bill address attributes are required' }, status: :unprocessable_entity
          return
        end
      end

      order = params[:order_id] ? Spree::Order.find(params[:order_id]) : current_order
      payment_method = Spree::PaymentMethod.find(params[:payment_method_id])
      service = SpreePaypal::PaypalService.new(payment_method)

      if order.update_from_params(params, permitted_checkout_attributes)
        Rails.logger.info "Order #{order.number} updated successfully from params"
      else
        Rails.logger.error "Order #{order.number} update failed: #{order.errors.full_messages.join(', ')}"
        render json: { error: 'Order update failed', details: order.errors.full_messages }, status: :unprocessable_entity
        return
      end

      order.reload
      if order.shipments.empty?
        Rails.logger.error "Order #{order.number} has no shipments after update_from_params"
        render json: { error: 'No shipments found for order' }, status: :unprocessable_entity
        return
      end
      response = service.authorize_order(params[:orderID])
      if response['status'] != 'COMPLETED'
        Rails.logger.error "PayPal authorization failed for order #{order.number}: #{response}"
        render json: { error: 'Authorization failed', details: response }, status: :unprocessable_entity
        return
      end

      begin
        process_spree_payment(order, payment_method, response)
      rescue => e
        Rails.logger.error "Payment processing failed for order #{order.number}: #{e.message}"
        render json: { error: 'Payment processing failed', details: e.message }, status: :unprocessable_entity
        return
      end

      begin
        order.next until order.completed? || order.errors.any?
        if order.errors.any?
          Rails.logger.error "Order #{order.number} failed to complete: #{order.errors.full_messages.join(', ')}"
          order.finalize!
        end
      rescue => e
        Rails.logger.error "Order finalization failed for #{order.number}: #{e.message}"
      end

      begin
        order.shipments.pending.each do |shipment|
          shipment.update(state: 'ready')
        end
      rescue => e
        Rails.logger.error "Shipment processing failed for order #{order.number}: #{e.message}"
      end

      order.update(shipment_state: 'ready')
      
      begin
        if params.dig('order', 'email_me') && order.ship_address.present?
          address = order.ship_address
          gibbon = ::Gibbon::Request.new(api_key: SpreeMailchimpEcommerce.configuration.mailchimp_api_key)
          gibbon.lists(::SpreeMailchimpEcommerce.configuration.mailchimp_list_id)
                .members
                .create(
                  body: {
                    email_address: order.email,
                    status: "subscribed",
                    merge_fields: {
                      FNAME: address.firstname,
                      LNAME: address.lastname,
                      ADDRESS: [
                        address.address1,
                        address.address2,
                        address.city,
                        address.state_name,
                        address.zipcode,
                        address.country_name
                      ].compact.join(', '),
                      PHONE: address.phone
                    }
                  }
                )
        end
      rescue => e
        Rails.logger.error "Mailchimp subscription failed for order #{order.number}: #{e.message}"
      end

      render json: { status: 'success', details: response }, status: :ok
    end

    private

    def process_spree_payment(order, payment_method, paypal_response)
      payer_info = paypal_response.dig('payer', 'name') || {}

      authorization_id = paypal_response.dig('purchase_units', 0, 'payments', 'authorizations', 0, 'id')
      if authorization_id.blank?
        raise "PayPal authorization id missing from response (PayPal order #{paypal_response['id']}); refusing to store an uncapturable response_code."
      end

      paypal_source = Spree::Paypal.create!(
        payer_id: paypal_response['payer']['payer_id'],
        first_name: payer_info['given_name'],
        last_name: payer_info['surname'],
        email: paypal_response['payer']['email_address'],
        payment_method_id: payment_method.id,
        transaction_id: paypal_response['id']
      )

      payment_attrs = {
        payment_method: payment_method,
        amount: order.outstanding_balance,
        state: 'pending',
        response_code: authorization_id,
        source: paypal_source,
        avs_response: paypal_response['payer']['payer_id']
      }

      payment = order.payments
                     .where(state: %w[checkout pending processing])
                     .order(created_at: :desc)
                     .first

      if payment
        payment.update!(payment_attrs)
      else
        order.payments.create!(payment_attrs)
      end
    end
  end
end
