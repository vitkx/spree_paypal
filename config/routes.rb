Spree::Core::Engine.routes.draw do
  post '/paypal/create_order', to: 'paypal#create_order'
  post '/paypal/authorize_order', to: 'paypal#authorize_order'
end
