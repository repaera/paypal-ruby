module Paypal
  # Provides functionality for managing payments, such as refunds and viewing capture/authorization details.
  # Interacts with PayPal Payments API v2.
  class Payment
    # @return [Paypal::Client] The API client instance.
    attr_reader :client

    # Creates a new Paypal::Payment instance.
    # @param client [Paypal::Client] (optional) An existing client instance.
    def initialize(client = Paypal::Client.new)
      @client = client
    end

    # Refunds a previously captured payment.
    # @param capture_id [String] The ID of the capture to be refunded.
    # @param amount [String, Numeric] (optional) The amount to refund. If nil, a full refund is attempted.
    # @param currency_code [String] The currency code (e.g., 'USD'), required if `amount` is set. Defaults to 'USD'.
    # @param note_to_payer [String] (optional) A note to the payer regarding the refund.
    # @param invoice_id [String] (optional) An invoice number for the refund.
    # @param paypal_request_id [String] (optional) A unique ID for request idempotency.
    # @return [Hash] The JSON response from PayPal containing refund details.
    # @raise [Paypal::ApiError] If an error occurs.
    # @see https://developer.paypal.com/docs/api/payments/v2/#captures_refund PayPal Refund Capture API
    def refund_capture(capture_id, amount: nil, currency_code: 'USD', note_to_payer: nil, invoice_id: nil, paypal_request_id: SecureRandom.uuid)
      payload = {}
      if amount.present?
        payload[:amount] = { currency_code: currency_code.to_s.upcase, value: amount.to_s }
      end
      payload[:note_to_payer] = note_to_payer if note_to_payer.present?
      payload[:invoice_id] = invoice_id if invoice_id.present?

      headers = { 'PayPal-Request-Id' => paypal_request_id }
      Paypal.log(:info, "Refunding PayPal capture ID: #{capture_id} with Request-Id: #{paypal_request_id}, Amount: #{amount}")
      client.post("/v2/payments/captures/#{capture_id}/refund", body: payload.empty? ? {} : payload, headers: headers)
    end

    # Shows details for a captured payment.
    # @param capture_id [String] The ID of the capture.
    # @return [Hash] The JSON response from PayPal containing capture details.
    # @raise [Paypal::ApiError] If an error occurs.
    # @see https://developer.paypal.com/docs/api/payments/v2/#captures_get PayPal Get Capture Details API
    def show_capture(capture_id)
      Paypal.log(:info, "Fetching PayPal capture details for ID: #{capture_id}")
      client.get("/v2/payments/captures/#{capture_id}")
    end

    # Shows details for an authorization.
    # @param authorization_id [String] The ID of the authorization.
    # @return [Hash] The JSON response from PayPal containing authorization details.
    # @raise [Paypal::ApiError] If an error occurs.
    # @see https://developer.paypal.com/docs/api/payments/v2/#authorizations_get PayPal Get Authorization Details API
    def show_authorization(authorization_id)
      Paypal.log(:info, "Fetching PayPal authorization details for ID: #{authorization_id}")
      client.get("/v2/payments/authorizations/#{authorization_id}")
    end

    # Voids (cancels) an authorized payment that has not yet been captured.
    # @param authorization_id [String] The ID of the authorization to void.
    # @param paypal_auth_assertion [String] (optional) A PayPal Auth Assertion header, sometimes required.
    # @return [Hash] Typically an empty response (HTTP 204 No Content) on success.
    # @raise [Paypal::ApiError] If an error occurs.
    # @see https://developer.paypal.com/docs/api/payments/v2/#authorizations_void PayPal Void Authorization API
    def void_authorization(authorization_id, paypal_auth_assertion: nil)
      headers = {}
      headers['PayPal-Auth-Assertion'] = paypal_auth_assertion if paypal_auth_assertion.present?
      Paypal.log(:info, "Voiding PayPal authorization ID: #{authorization_id}")
      # According to PayPal docs, voiding an authorization is a POST request.
      client.post("/v2/payments/authorizations/#{authorization_id}/void", body: {}, headers: headers)
    end

    # Captures a previously authorized payment.
    # @param authorization_id [String] The ID of the authorization to capture.
    # @param amount [String, Numeric] (optional) The amount to capture. If nil, the full authorized amount is captured.
    # @param currency_code [String] The currency code, required if `amount` is set. Defaults to 'USD'.
    # @param final_capture [Boolean] Indicates if this is the final capture for the authorization. Defaults to true.
    # @param invoice_id [String] (optional) An invoice number for the capture.
    # @param note_to_payer [String] (optional) A note to the payer.
    # @param paypal_request_id [String] (optional) A unique ID for request idempotency.
    # @return [Hash] The JSON response from PayPal containing capture details.
    # @raise [Paypal::ApiError] If an error occurs.
    # @see https://developer.paypal.com/docs/api/payments/v2/#authorizations_capture PayPal Capture Authorization API
    def capture_authorization(authorization_id, amount: nil, currency_code: 'USD', final_capture: true, invoice_id: nil, note_to_payer: nil, paypal_request_id: SecureRandom.uuid)
      payload = { final_capture: final_capture }
      if amount.present?
        payload[:amount] = { currency_code: currency_code.to_s.upcase, value: amount.to_s }
      end
      payload[:invoice_id] = invoice_id if invoice_id.present?
      payload[:note_to_payer] = note_to_payer if note_to_payer.present?

      headers = { 'PayPal-Request-Id' => paypal_request_id }
      Paypal.log(:info, "Capturing PayPal authorization ID: #{authorization_id} with Request-Id: #{paypal_request_id}, Amount: #{amount}")
      client.post("/v2/payments/authorizations/#{authorization_id}/capture", body: payload, headers: headers)
    end
  end
end