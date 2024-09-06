# SpreePaypal

SpreePaypal is a gem that integrates PayPal's REST API with the Spree eCommerce platform. It creates a new PayPal payment method, supports the PayPal JavaScript SDK for frontend payment processing, and allows you to configure sandbox or live modes for testing and production.


## Installation

1. Add this line to your application's Gemfile:

    ```ruby
    gem 'spree_paypal', github: 'vitkx/spree_paypal', branch: 'master'
    ```

2. Install the gem by running:

    ```bash
    bundle install
    ```

3. Copy & run migrations

    ```bash
    bundle exec rails g spree_paypal:install
    ```

4. Restart your server


## Usage

After installation, configure PayPal by adding your `client_id`, `client_secret`, and sandbox settings in the Spree admin panel under **Payment Methods**.


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/vitkx/spree_paypal.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
