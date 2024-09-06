module SpreePaypal
  class Engine < Rails::Engine
    require 'spree/core'
    isolate_namespace Spree
    engine_name 'spree_paypal'

    config.after_initialize do |app|
      app.config.spree.payment_methods += [
        Spree::PaymentMethod::Paypal,
      ]
    end
  end
end