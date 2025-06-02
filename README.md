# PayPal Ruby

A PayPal REST API wrapper for Ruby, including Payouts and basic Marketplace features. Provides quicker method on client side to interact with the PayPal REST API(Last ref: 02-06-2025).

## Features

* OAuth 2.0 authentication with PayPal.
* Orders API v2: Create, show, capture, authorize.
* Marketplace: `platform_fees` support for orders.
* Payments API v2: Refund captures, show capture/authorization details.
* Payouts API v1: Create single and batch payouts, show details, cancel unclaimed items.
* Webhook signature verification.
* Custom error classes for clear error handling.
* Bare minimum configuration.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'paypal', git: 'https://github.com/repaera/paypal-ruby.git'
```

Or if you are building it locally:

```ruby
gem 'paypal', path: '../path/to/your/paypal' # Path to your gem directory
```

And then execute:

```bash
$ bundle install
```

## Configuration

Create an initializer file (e.g., `config/initializers/paypal.rb` if in Rails, or configure directly):

```ruby
# config/initializers/paypal.rb (Example for Rails)
Paypal.configure do |config|
  config.client_id = ENV['PAYPAL_CLIENT_ID']
  config.client_secret = ENV['PAYPAL_CLIENT_SECRET']
  config.mode = ENV.fetch('PAYPAL_MODE', (defined?(Rails) && Rails.env.production? ? 'live' : 'sandbox'))
  config.webhook_id = ENV['PAYPAL_WEBHOOK_ID']
  config.logger = defined?(Rails) ? Rails.logger : Logger.new($stdout)
  config.payout_sender_batch_header_note = "Your Payout from Our Platform"
end
```

Ensure you have set the necessary environment variables (e.g., `PAYPAL_CLIENT_ID`, `PAYPAL_CLIENT_SECRET`, `PAYPAL_WEBHOOK_ID`) or use Rails credentials.

## Usage

### 1. API Client

You can instantiate a client manually, but typically, the service objects (Order, Payment, Payout, WebhookVerifier) will create one internally.

```ruby
client = Paypal::Client.new
# Available methods: client.get(path, query: {}, headers: {})
#                    client.post(path, body: {}, headers: {})
#                    client.patch(path, body: {}, headers: {})
#                    client.delete(path, headers: {})
```

### 2. Orders

```ruby
order_service = Paypal::Order.new

# Create a standard order
begin
  purchase_units = [{
    amount: { currency_code: 'USD', value: '10.99' },
    description: 'Purchase Item'
  }]
  app_context = {
    return_url: 'https://yourapp.com/paypal/return', # REPLACE with your actual return URL
    cancel_url: 'https://yourapp.com/paypal/cancel',  # REPLACE with your actual cancel URL
    brand_name: 'Your Store Name',
    shipping_preference: 'NO_SHIPPING'
  }
  response = order_service.create(
    intent: 'CAPTURE',
    purchase_units: purchase_units,
    application_context: app_context
  )
  # response['id'] is the PayPal order ID
  # response['links'] contains the 'approve' link for redirection
  approval_link = response['links'].find { |link| link['rel'] == 'approve' }
  if approval_link
    # In a Rails controller:
    # redirect_to approval_link['href'], allow_other_host: true
    puts "Redirect user to: #{approval_link['href']}"
  else
    puts "Error: No approval link found."
  end
rescue Paypal::ApiError => e
  puts "PayPal Error: #{e.message} (Debug ID: #{e.paypal_debug_id})"
  # Handle specific errors like Paypal::BadRequestError, etc.
end

# Create an order with commission splitting (Marketplace)
currency = 'USD'
customer_pays = 100.00
platform_fee_amount = 10.00 # Your platform's commission
marketplace_merchant_id = 'MARKETPLACE_PAYPAL_MERCHANT_ID' # Service provider's PayPal Merchant ID

payment_source_payload = {
  paypal: {
    experience_context: { # Similar to application_context
      return_url: 'https://yourapp.com/paypal/return', # REPLACE
      cancel_url: 'https://yourapp.com/paypal/cancel',   # REPLACE
      brand_name: 'Your Platform',
      user_action: 'PAY_NOW'
    },
    payment_instruction: {
      platform_fees: [{
        amount: { currency_code: currency, value: platform_fee_amount.to_s }
        # payee can be set if the fee is for an account other than the API caller
      }],
      disbursement_mode: 'INSTANT' # or 'DELAYED'
    }
  }
}
purchase_units_marketplace = [{
  amount: { currency_code: currency, value: customer_pays.to_s },
  payee: { merchant_id: marketplace_merchant_id }, # Primary recipient
  description: "Service X by Provider Y"
}]

begin
  response = order_service.create(
    intent: 'CAPTURE',
    purchase_units: purchase_units_marketplace,
    payment_source: payment_source_payload
  )
  # ... process redirect ...
rescue Paypal::ApiError => e
  puts "PayPal Marketplace Order Error: #{e.message}"
end


# Show order details
order_id = 'PAYPAL_ORDER_ID'
details = order_service.show(order_id)

# Capture a payment
# (Usually done after the customer approves on the PayPal page and is redirected back)
order_id_from_callback = '...'
capture_response = order_service.capture(order_id_from_callback)
if capture_response['status'] == 'COMPLETED'
  # Payment successful
  paypal_capture_id = capture_response.dig('purchase_units', 0, 'payments', 'captures', 0, 'id')
end

# Authorize a payment
auth_response = order_service.authorize(order_id_from_callback)
```

### 3. Payments (for Refunds, etc.)

```ruby
payment_service = Paypal::Payment.new
capture_id = 'PAYPAL_CAPTURE_ID' # Obtained from the order capture response

# Refund a payment
begin
  refund_response = payment_service.refund_capture(
    capture_id,
    amount: '5.00', # Optional, for partial refund
    currency_code: 'USD',
    note_to_payer: 'Refund for item X'
  )
  if refund_response['status'] == 'COMPLETED'
    # Refund successful
  end
rescue Paypal::ApiError => e
  puts "PayPal Refund Error: #{e.message}"
end

# Show capture details
capture_details = payment_service.show_capture(capture_id)
```

### 4. Payouts (Sending Money)

Ensure your PayPal account is approved for Payouts API.

```ruby
payout_service = Paypal::Payout.new

# Single Payout
begin
  response = payout_service.create_single(
    recipient_type: 'EMAIL',
    receiver: 'recipient@example.com',
    amount: '25.50',
    currency: 'USD',
    note: 'Payment for your services',
    sender_item_id: "payout_item_#{SecureRandom.uuid}" # Your unique ID
  )
  response['batch_header']['payout_batch_id']
  # Monitor status via webhooks or show_batch/show_item
rescue Paypal::PayoutError => e # Specific error for Payouts
  puts "Payout Error: #{e.message}"
end

# Batch Payout
items_to_payout = [
  { recipient_type: 'EMAIL', receiver: 'recipient1@example.com', amount: { value: '10.00', currency: 'USD' }, note: 'Payment A', sender_item_id: 'item_A1' },
  { recipient_type: 'PAYPAL_ID', receiver: 'PAYPAL_ID_RECIPIENT2', amount: { value: '15.75', currency: 'USD' }, note: 'Payment B', sender_item_id: 'item_B2' }
]
begin
  batch_response = payout_service.create_batch(
    items: items_to_payout,
    subject: "Your Weekly Payout",
    sender_batch_id: "weekly_payout_#{Time.now.strftime('%Y%m%d_%H%M')}" # Optional
  )
  payout_batch_id = batch_response.dig('batch_header', 'payout_batch_id')
  # Store payout_batch_id to track status
rescue Paypal::PayoutError => e
  puts "Batch Payout Error: #{e.message}"
end

# Show payout batch details
batch_details = payout_service.show_batch(payout_batch_id)

# Show payout item details
item_id_from_webhook_or_batch_details = '...'
item_details = payout_service.show_item(item_id_from_webhook_or_batch_details)

# Cancel an unclaimed payout item
cancel_response = payout_service.cancel_unclaimed_item(item_id_from_webhook_or_batch_details)
```

### 5. Webhook Verification

Create a controller in your application (e.g., Rails) to receive webhook notifications from PayPal.

```ruby
# Example Rails Controller: app/controllers/paypal_webhooks_controller.rb
class PaypalWebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token # Important for external webhooks

  def receive
    webhook_event_body = request.raw_post # Raw JSON body
    # Get required headers from the request
    auth_algo = request.headers['PAYPAL-AUTH-ALGO']
    cert_url = request.headers['PAYPAL-CERT-URL']
    transmission_id = request.headers['PAYPAL-TRANSMISSION-ID']
    transmission_sig = request.headers['PAYPAL-TRANSMISSION-SIG']
    transmission_time = request.headers['PAYPAL-TRANSMISSION-TIME']

    verifier = Paypal::WebhookVerifier.new
    begin
      is_verified = verifier.verify_signature(
        auth_algo: auth_algo,
        cert_url: cert_url,
        transmission_id: transmission_id,
        transmission_sig: transmission_sig,
        transmission_time: transmission_time,
        webhook_event_body: webhook_event_body
      )

      if is_verified
        event_payload = JSON.parse(webhook_event_body)
        Paypal.log(:info, "Webhook signature verified. Event: #{event_payload['event_type']}")
        
        # Process the event (ideally in a background job)
        # Example: PaypalWebhookProcessorJob.perform_later(event_payload)
        # process_paypal_event(event_payload) 
        
        head :ok # Send HTTP 200 OK to PayPal
      else
        Paypal.log(:warn, "Webhook signature verification failed.")
        head :unauthorized
      end
    rescue Paypal::WebhookVerificationError => e
      Paypal.log(:error, "Webhook verification error: #{e.message}")
      head :bad_request # Or :internal_server_error depending on the error type
    rescue JSON::ParserError => e
      Paypal.log(:error, "Webhook JSON parsing error: #{e.message}")
      head :bad_request
    rescue StandardError => e
      Paypal.log(:error, "Unexpected error in webhook controller: #{e.message}")
      head :internal_server_error
    end
  end

  # private
  # def process_paypal_event(payload)
  #   # Your business logic to handle various PayPal event types
  # end
end
```

Don't forget to add the route in `config/routes.rb` (for Rails):
`post '/webhooks/paypal', to: 'paypal_webhooks#receive'`

## Error Handling

This gem raises specific error classes inheriting from `Paypal::ApiError` or `Paypal::Error`. Refer to `lib/paypal/errors.rb` for details. `Paypal::ApiError` instances include `response_code`, `response_body`, and `paypal_debug_id` attributes, which can be useful for debugging.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `bundle exec rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`.

## Contributing

Bug reports and pull requests are welcome on GitHub at [YOUR REPO URL for 'paypal' gem]. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](http://contributor-covenant.org) code of conduct.

1.  Fork the repository (`https://github.com/repaera/paypal-ruby/fork`)
2.  Create your feature branch (`git checkout -b my-new-feature`)
3.  Commit your changes (`git commit -am 'Add some feature'`)
4.  Push to the branch (`git push origin my-new-feature`)
5.  Create a new Pull Request

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the **repaera/paypal-ruby** project's codebase, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/repaera/paypal-ruby/blob/main/CODE_OF_CONDUCT.md) (if you create one).
