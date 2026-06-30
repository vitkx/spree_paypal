module Spree
  class Paypal < ApplicationRecord
    belongs_to :payment_method, class_name: 'Spree::PaymentMethod'

    validates :payer_id, :first_name, :last_name, :email, presence: true

     def actions
      %w[credit]
    end
  end
end

