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

    def auto_capture?
      true
    end

    def supports?(source)
      source.payment_method.is_a?(Spree::PaymentMethod::Paypal)
    end

    def provider_class
      ::PaypalService
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
  end
end