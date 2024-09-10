module Spree
  module Api
    module V2
      module Platform
        class PaypalSerializer < BaseSerializer
          set_type :paypal

          attributes :payer_id, :email_address, :first_name, :last_name

          # Add other attributes or associations as needed
        end
      end
    end
  end
end