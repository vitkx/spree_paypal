module Spree
  class PaymentMethod::Paypal < PaymentMethod
    preference :client_id, :string
    preference :client_secret, :string
    preference :sandbox, :boolean, default: true # Default to sandbox mode

    def payment_source_class
      Spree::Paypal
    end

    def actions
      %w{capture void}
    end

    def purchase(amount, source, options = {})
      ActiveMerchant::Billing::Response.new(true, 'Paypal Gateway', {})
    end

    def auto_capture?
      true
    end

    def supports?(source)
      source.payment_method.is_a?(Spree::PaymentMethod::Paypal)
    end

    def capture(response_code, amount, currency)
      result = provider_class.new(self).capture_authorized_payment(response_code, amount, currency)

      if result['name'] == 'RESOURCE_NOT_FOUND'
        ActiveMerchant::Billing::Response.new(false, 'The specified PayPal resource does not exist', result)
      else
        payment = Spree::Payment.find_by(response_code: response_code)
        payment.update!(response_code: result['id'], amount: amount) if payment
        ActiveMerchant::Billing::Response.new(true, 'PayPal payment captured', result)
      end
    rescue => e
      ActiveMerchant::Billing::Response.new(false, e.message, {})
    end

    def reauthorize(response_code, order, payment)
      result = provider_class.new(self).void_and_authorize(response_code,order)
      ActiveMerchant::Billing::Response.new(true, 'PayPal payment reauthorized', result)
      payment.update!(response_code: result['authorization_id']) if payment
    rescue => e
      ActiveMerchant::Billing::Response.new(false, e.message, {})
    end

    def provider_class
      SpreePaypal::PaypalService
    end

    def client_id
      preferred_client_id
    end

    def client_secret
      preferred_client_secret
    end

    def sandbox?
      preferred_sandbox
    end

    def cancel(response_code, payment)
      result = {}
      
      if payment.state == 'pending'
        result = provider_class.new(self).void_authorization(response_code)
      else
        result = provider_class.new(self).refund_by_capture_id(response_code, payment.amount, payment)
      end

      if result['name'] == 'RESOURCE_NOT_FOUND'
        ActiveMerchant::Billing::Response.new(false, 'The specified PayPal resource does not exist', result)
      else
        ActiveMerchant::Billing::Response.new(true, 'PayPal payment refunded', result)
      end
    rescue => e
      ActiveMerchant::Billing::Response.new(false, e.message, {})
    end

    def credit(amount_cents, response_code, options = {})
      amount = BigDecimal(amount_cents) / 100

      result = provider_class.new(self).refund_by_capture_id(response_code, amount, options[:originator])

      ActiveMerchant::Billing::Response.new(true, 'PayPal payment refunded', result)
    rescue => e
      ActiveMerchant::Billing::Response.new(false, e.message, {})
    end
  end
end
