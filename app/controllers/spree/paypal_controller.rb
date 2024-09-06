module Spree
  class PaypalController < Spree::StoreController
    protect_from_forgery with: :null_session

    def create_order
      order = current_order
      payment_method = Spree::PaymentMethod.find(params[:payment_method_id])

      service = SpreePaypal::PaypalService.new(payment_method)
      response = service.create_order(order)

      if response['id']
        render json: { orderID: response['id'] }, status: :ok
      else
        render json: { error: response['message'] }, status: :unprocessable_entity
      end
    end

    def capture_order
      order = current_order
      payment_method = Spree::PaymentMethod.find(params[:payment_method_id])
      service = SpreePaypal::PaypalService.new(payment_method)
      response = service.capture_order(params[:orderID])

      if response['status'] == 'COMPLETED'
        process_spree_payment(order, payment_method, response)
        render json: { status: 'success', details: response }, status: :ok
      else
        render json: { error: 'Capture failed' }, status: :unprocessable_entity
      end
    end

    private

    def process_spree_payment(order, payment_method, paypal_response)
      payer_info = paypal_response.dig('payer', 'name') || {}

      paypal_source = Spree::Paypal.create!(
        payer_id: paypal_response['payer']['payer_id'],
        first_name: payer_info['given_name'],
        last_name: payer_info['surname'],
        email: paypal_response['payer']['email_address'],
        payment_method_id: payment_method.id,
        transaction_id: paypal_response['id']
      )

      payment = order.payments.create!(
        payment_method: payment_method,
        amount: order.total,
        state: 'completed',
        response_code: paypal_response['id'],
        source: paypal_source, # You could create a PayPal-specific payment source if necessary
        avs_response: paypal_response['payer']['payer_id']
      )

      # Only transition the order if it's not already completed
      if order.state != 'complete'
        order.next! if order.state == 'payment'
      end
      payment.complete! unless payment.completed?
    end
  end
end