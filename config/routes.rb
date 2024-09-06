Spree::Core::Engine.routes.draw do
  post '/paypal/create_order', to: 'paypal#create_order'
  post '/paypal/capture_order', to: 'paypal#capture_order'
end