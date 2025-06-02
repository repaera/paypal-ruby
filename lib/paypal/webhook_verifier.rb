module Paypal
  # Verifies the authenticity of incoming PayPal webhook notifications.
  # Uses the PayPal Webhooks API v1 for signature verification.
  class WebhookVerifier
    # @return [Paypal::Client] The API client instance.
    attr_reader :client
    # @return [Paypal::Configuration] The current gem configuration.
    attr_reader :config

    # Creates a new Paypal::WebhookVerifier instance.
    # @param client [Paypal::Client] (optional) An existing client instance.
    # @raise [Paypal::ConfigurationError] if `webhook_id` is not configured.
    def initialize(client = Paypal::Client.new)
      @client = client
      @config = Paypal.current_configuration
      validate_configuration!
    end

    # Verifies the signature of a PayPal webhook event.
    #
    # @param auth_algo [String] The value of the `PAYPAL-AUTH-ALGO` header.
    # @param cert_url [String] The value of the `PAYPAL-CERT-URL` header.
    # @param transmission_id [String] The value of the `PAYPAL-TRANSMISSION-ID` header.
    # @param transmission_sig [String] The value of the `PAYPAL-TRANSMISSION-SIG` header.
    # @param transmission_time [String] The value of the `PAYPAL-TRANSMISSION-TIME` header.
    # @param webhook_event_body [String] The raw JSON string body of the webhook request.
    # @return [Boolean] `true` if the signature is verified successfully, `false` otherwise.
    # @raise [Paypal::WebhookVerificationError] If an error occurs during the verification API call or due to invalid input.
    # @raise [Paypal::ConfigurationError] if `webhook_id` is not configured.
    # @see https://developer.paypal.com/docs/api/webhooks/v1/#verify-webhook-signature_post PayPal Verify Webhook Signature API
    def verify_signature(auth_algo:, cert_url:, transmission_id:, transmission_sig:, transmission_time:, webhook_event_body:)
      webhook_id_to_verify = config.webhook_id # Already validated in initialize

      unless auth_algo.present? && cert_url.present? && transmission_id.present? && transmission_sig.present? && transmission_time.present?
        Paypal.log(:warn, "Webhook verification failed: Missing one or more required headers.")
        return false
      end

      begin
        parsed_event_body = JSON.parse(webhook_event_body)
      rescue JSON::ParserError => e
        Paypal.log(:error, "Webhook verification failed: Could not parse webhook_event_body. Error: #{e.message}")
        raise Paypal::WebhookVerificationError, "Invalid JSON in webhook event body: #{e.message}"
      end

      payload = {
        auth_algo: auth_algo,
        cert_url: cert_url,
        transmission_id: transmission_id,
        transmission_sig: transmission_sig,
        transmission_time: transmission_time,
        webhook_id: webhook_id_to_verify,
        webhook_event: parsed_event_body # Send parsed JSON object
      }

      Paypal.log(:info, "Attempting to verify webhook signature for Transmission ID: #{transmission_id}")
      begin
        response = client.post('/v1/notifications/verify-webhook-signature', body: payload)
      rescue Paypal::ApiError => e # Catch API errors from the client.post call
        Paypal.log(:error, "Webhook verification API call failed: #{e.message} (Debug ID: #{e.paypal_debug_id})")
        raise Paypal::WebhookVerificationError, "API call to PayPal for webhook verification failed: #{e.message}"
      end

      if response && response['verification_status'] == 'SUCCESS'
        Paypal.log(:info, "Webhook signature VERIFIED for Transmission ID: #{transmission_id}")
        return true
      else
        error_message = response ? response['message'] : "Unknown error during verification."
        Paypal.log(:warn, "Webhook signature VERIFICATION FAILED for Transmission ID: #{transmission_id}. Status: #{response&.[]('verification_status')}. Message: #{error_message}. Details: #{response&.[]('details')}")
        return false
      end

    # Catch StandardError for truly unexpected issues, JSON::ParserError is handled above.
    rescue StandardError => e
      Paypal.log(:error, "Unexpected error during webhook verification: #{e.class.name} - #{e.message}\n#{e.backtrace.join("\n")}")
      # Re-raise as a WebhookVerificationError to provide a consistent error type from this method.
      raise Paypal::WebhookVerificationError, "An unexpected error occurred during webhook signature verification: #{e.message}"
    end

    private

    # @!visibility private
    def validate_configuration!
      raise Paypal::ConfigurationError, "PayPal webhook_id is not configured in Paypal module." if config.webhook_id.blank?
    end
  end
end