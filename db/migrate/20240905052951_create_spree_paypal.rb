# frozen_string_literal: true

# This migration comes from spree_paypal_express (originally 20130723042610)
class CreateSpreePaypal < SpreeExtension::Migration[4.2]
  def change
    unless table_exists?(:spree_paypals)
      create_table :spree_paypals do |t|
        t.string :email
        t.string :first_name
        t.string :last_name
        t.string :payer_id
        t.string :transaction_id
        t.bigint :payment_method_id
      end
    end
  end
end
