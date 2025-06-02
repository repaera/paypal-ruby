module Paypal
  # Provides functionality to interact with the PayPal Payouts API v1.
  # Allows sending single or batch payouts to multiple recipients.
  # Ensure your PayPal account is approved for Payouts API usage.
  class Payout
    # @return [Paypal::Client] The API client instance.
    attr_reader :client
    # @return [Paypal::Configuration] The current gem configuration.
    attr_reader :config

    # Creates a new Paypal::Payout instance.
    # @param client [Paypal::Client] (optional) An existing client instance.
    def initialize(client = Paypal::Client.new)
      @client = client
      @config = Paypal.current_configuration
    end

    # Creates a single payout item. This is processed asynchronously as part of a batch.
    #
    # @param recipient_type [String] The type of recipient identifier ('EMAIL', 'PHONE', or 'PAYPAL_ID').
    # @param receiver [String] The recipient's identifier (email, phone number, or PayPal Payer ID).
    # @param amount [String, Numeric] The amount to send.
    # @param currency [String] The currency code (e.g., 'USD').
    # @param note [String] A note for the recipient.
    # @param sender_item_id [String] A unique ID for this payout item from your system.
    # @param subject [String] (optional) The subject of the email notification sent to the recipient.
    #   Defaults to `config.payout_sender_batch_header_note` or a generic message.
    # @return [Hash] The JSON response from PayPal, containing `payout_batch_id` and initial status.
    # @raise [Paypal::PayoutError] If a Payouts API specific error occurs.
    # @raise [Paypal::ApiError] For other API errors.
    # @see [https://developer.paypal.com/docs/api/payments.payouts-batch/v1/#payouts_post](https://developer.paypal.com/docs/api/payments.payouts-batch/v1/#payouts_post) PayPal Create Payout API
    def create_single(recipient_type:, receiver:, amount:, currency:, note:, sender_item_id:, subject: nil)
      begin
        batch_note = subject || config.payout_sender_batch_header_note || "You have a new payout!"
        payload = {
            sender_batch_header: {
            sender_batch_id: "single_payout_#{SecureRandom.uuid}", # Unique batch ID for this single payout
            email_subject: batch_note
            # recipient_type can be defined here if all items in a batch share it.
            # However, for clarity and consistency with batch payouts, it's often set per item.
            },
            items: [
            {
                recipient_type: recipient_type.to_s.upcase,
                receiver: receiver,
                amount: { value: amount.to_s, currency: currency.to_s.upcase },
                note: note,
                sender_item_id: sender_item_id
            }
            ]
        }
        Paypal.log(:info, "Creating single payout to: #{receiver}, Amount: #{amount} #{currency}, Sender Item ID: #{sender_item_id}")
        client.post('/v1/payments/payouts', body: payload)
      rescue Paypal::BadRequestError => e
        raise Paypal::PayoutError, e.message if e.message.include?("VALIDATION_ERROR")
        raise
      end
    end

    # Creates a batch payout to multiple recipients. Processed asynchronously.
    #
    # @param items [Array<Hash>] An array of payout items. Each item hash should include:
    #   - `:recipient_type` [String] ('EMAIL', 'PHONE', 'PAYPAL_ID')
    #   - `:receiver` [String] Recipient's identifier.
    #   - `:amount` [Hash] e.g., `{ value: '10.00', currency: 'USD' }`
    #   - `:note` [String] Note for the recipient.
    #   - `:sender_item_id` [String] Your unique ID for this item.
    # @param sender_batch_id [String] (optional) A unique ID for this batch. If nil, one is generated.
    # @param subject [String] (optional) The subject for email notifications for this batch.
    #   Defaults to `config.payout_sender_batch_header_note` or a generic message.
    # @param note_for_batch [String] (optional) A note for the `sender_batch_header`.
    # @return [Hash] The JSON response from PayPal, containing `payout_batch_id`.
    # @raise [Paypal::PayoutError] If a Payouts API specific error occurs.
    # @raise [Paypal::ApiError] For other API errors.
    def create_batch(items:, sender_batch_id: nil, subject: nil, note_for_batch: nil)
      batch_id = sender_batch_id || "batch_payout_#{SecureRandom.uuid}"
      email_subject_for_batch = subject || config.payout_sender_batch_header_note || "You have new payouts!"

      formatted_items = items.map do |item|
        {
          recipient_type: item[:recipient_type]&.to_s&.upcase || 'EMAIL', # Default to EMAIL
          receiver: item[:receiver],
          amount: {
            value: item.dig(:amount, :value).to_s,
            currency: item.dig(:amount, :currency)&.to_s&.upcase || 'USD' # Default to USD
          },
          note: item[:note],
          sender_item_id: item[:sender_item_id]
        }
      end

      payload = {
        sender_batch_header: {
          sender_batch_id: batch_id,
          email_subject: email_subject_for_batch,
          note: note_for_batch # Note for the batch header itself
        },
        items: formatted_items
      }
      Paypal.log(:info, "Creating batch payout. Batch ID: #{batch_id}, Items count: #{items.size}")
      client.post('/v1/payments/payouts', body: payload)
    end

    # Shows details for a specific payout batch.
    # @param payout_batch_id [String] The ID of the payout batch (returned from `create_batch` or `create_single`).
    # @return [Hash] The JSON response from PayPal with batch details.
    # @raise [Paypal::ApiError] If an error occurs.
    # @see [https://developer.paypal.com/docs/api/payments.payouts-batch/v1/#payouts_get](https://developer.paypal.com/docs/api/payments.payouts-batch/v1/#payouts_get) PayPal Get Payout Batch Details API
    def show_batch(payout_batch_id)
      Paypal.log(:info, "Fetching payout batch details for ID: #{payout_batch_id}")
      client.get("/v1/payments/payouts/#{payout_batch_id}")
    end

    # Shows details for a single payout item within a batch.
    # @param payout_item_id [String] The ID of the payout item (obtained from batch details or webhooks).
    # @return [Hash] The JSON response from PayPal with item details.
    # @raise [Paypal::ApiError] If an error occurs.
    # @see [https://developer.paypal.com/docs/api/payments.payouts-batch/v1/#payouts-item_get](https://developer.paypal.com/docs/api/payments.payouts-batch/v1/#payouts-item_get) PayPal Get Payout Item Details API
    def show_item(payout_item_id)
      Paypal.log(:info, "Fetching payout item details for ID: #{payout_item_id}")
      client.get("/v1/payments/payouts-item/#{payout_item_id}")
    end

    # Cancels an unclaimed payout item.
    # An item can be canceled if its status is UNCLAIMED.
    # @param payout_item_id [String] The ID of the payout item to cancel.
    # @return [Hash] The JSON response from PayPal, typically confirming cancellation.
    # @raise [Paypal::ApiError] If an error occurs (e.g., item not cancellable).
    # @see [https://developer.paypal.com/docs/api/payments.payouts-batch/v1/#payouts-item_cancel](https://developer.paypal.com/docs/api/payments.payouts-batch/v1/#payouts-item_cancel) PayPal Cancel Payout Item API
    def cancel_unclaimed_item(payout_item_id)
      Paypal.log(:info, "Attempting to cancel unclaimed payout item ID: #{payout_item_id}")
      # API Payouts v1 for cancel is POST to the item's endpoint with /cancel
      client.post("/v1/payments/payouts-item/#{payout_item_id}/cancel", body: {}) # POST with empty body
    end
  end
end