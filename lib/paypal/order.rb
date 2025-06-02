module Paypal
  # Provides functionality to interact with the PayPal Orders API v2.
  # Allows creating, showing, authorizing, capturing, and updating orders.
  class Order
    # @return [Paypal::Client] The API client instance used for requests.
    attr_reader :client

    # Creates a new Paypal::Order instance.
    # @param client [Paypal::Client] (optional) An existing client instance.
    #   If not provided, a new client will be created internally.
    def initialize(client = Paypal::Client.new)
      @client = client
    end

    # Creates a new PayPal order.
    #
    # @param intent [String] The intent of the order, typically 'CAPTURE' or 'AUTHORIZE'.
    # @param purchase_units [Array<Hash>] An array describing the items or amounts for purchase.
    #   Each hash must contain at least `amount: { currency_code: 'USD', value: '10.00' }`.
    #   For marketplace scenarios, `payee: { merchant_id: 'MERCHANT_ID' }` is also crucial here.
    # @param application_context [Hash] (optional) Application context such as return URLs, brand name, etc.
    #   Used if `payment_source` is not provided or does not have its own `experience_context`.
    # @param payment_source [Hash] (optional) Used for marketplace scenarios, especially for
    #   defining `platform_fees` and `payment_instruction`. If present, its `experience_context`
    #   will override `application_context`.
    # @option payment_source [Hash] :paypal A hash containing PayPal-specific details.
    # @option payment_source[:paypal] [Hash] :experience_context User experience context.
    # @option payment_source[:paypal] [Hash] :payment_instruction Payment instructions, including `platform_fees`.
    # @return [Hash] The JSON response from PayPal containing details of the created order, including ID and approval links.
    # @raise [Paypal::ApiError] If an error occurs while communicating with the PayPal API.
    # @see [https://developer.paypal.com/docs/api/orders/v2/#orders_create](https://developer.paypal.com/docs/api/orders/v2/#orders_create) PayPal Orders Create API
    # @see [https://developer.paypal.com/docs/multiparty/checkout/advanced/](https://developer.paypal.com/docs/multiparty/checkout/advanced/) PayPal Marketplace Checkout
    #
    # @example Creating a standard order
    #   order_service.create(
    #     intent: 'CAPTURE',
    #     purchase_units: [{ amount: { currency_code: 'USD', value: '20.00' } }],
    #     application_context: { return_url: '...', cancel_url: '...' }
    #   )
    #
    # @example Creating a marketplace order with a platform fee
    #   order_service.create(
    #     intent: 'CAPTURE',
    #     purchase_units: [{
    #       amount: { currency_code: 'USD', value: '100.00' },
    #       payee: { merchant_id: 'SELLER_MERCHANT_ID' } # The primary recipient of funds
    #     }],
    #     payment_source: {
    #       paypal: {
    #         experience_context: { return_url: '...', cancel_url: '...' },
    #         payment_instruction: {
    #           platform_fees: [{ amount: { currency_code: 'USD', value: '5.00' } }], # Platform's commission
    #           disbursement_mode: 'INSTANT' # How funds are disbursed
    #         }
    #       }
    #     }
    #   )
    def create(intent:, purchase_units:, application_context: {}, payment_source: nil)
      payload = {
        intent: intent.to_s.upcase,
        purchase_units: purchase_units
      }

      if payment_source.present?
        payload[:payment_source] = payment_source
        # If application_context is also provided, merge it into payment_source's experience_context if not already there.
        if application_context.present? && payment_source.dig(:paypal, :experience_context).blank?
          payload[:payment_source][:paypal] ||= {}
          payload[:payment_source][:paypal][:experience_context] = application_context
        elsif application_context.present? && payment_source.dig(:paypal, :experience_context).present?
          Paypal.log(:warn, "Both application_context and payment_source.paypal.experience_context are provided. Using payment_source's context.")
        end
      elsif application_context.present?
        payload[:application_context] = application_context
      end

      Paypal.log(:info, "Creating PayPal order with intent: #{intent}. Payload: #{payload.to_json}")
      client.post('/v2/checkout/orders', body: payload)
    end

    # Shows details for an existing PayPal order.
    # @param order_id [String] The ID of the PayPal order to show.
    # @return [Hash] The JSON response from PayPal containing order details.
    # @raise [Paypal::NotFoundError] If the order_id is not found.
    # @raise [Paypal::ApiError] For other API errors.
    # @see [https://developer.paypal.com/docs/api/orders/v2/#orders_get](https://developer.paypal.com/docs/api/orders/v2/#orders_get) PayPal Orders Get API
    def show(order_id)
      Paypal.log(:info, "Fetching PayPal order details for ID: #{order_id}")
      client.get("/v2/checkout/orders/#{order_id}")
    end

    # Captures the payment for an order that has been approved by the customer.
    # @param order_id [String] The PayPal order ID.
    # @param paypal_request_id [String] (optional) A unique ID for request idempotency. Defaults to a new UUID.
    # @param payment_source [Hash] (optional) For marketplace scenarios, if specific payment
    #   instructions are needed at capture time (e.g., if payee was not set at `create`).
    # @return [Hash] The JSON response from PayPal containing capture details.
    # @raise [Paypal::ApiError] If an error occurs.
    # @see [https://developer.paypal.com/docs/api/orders/v2/#orders_capture](https://developer.paypal.com/docs/api/orders/v2/#orders_capture) PayPal Orders Capture API
    def capture(order_id, paypal_request_id: SecureRandom.uuid, payment_source: nil)
      headers = { 'PayPal-Request-Id' => paypal_request_id }
      body_payload = {} # Initialize as empty hash
      body_payload[:payment_source] = payment_source if payment_source.present?

      Paypal.log(:info, "Capturing PayPal order ID: #{order_id} with Request-Id: #{paypal_request_id}. Body: #{body_payload.to_json}")
      # Ensure body is only sent if not empty, or send {} as per API spec
      client.post("/v2/checkout/orders/#{order_id}/capture", body: body_payload.empty? ? {} : body_payload, headers: headers)
    end

    # Authorizes a payment for an order. Funds are held but not yet transferred.
    # @param order_id [String] The PayPal order ID.
    # @param paypal_request_id [String] (optional) A unique ID for idempotency.
    # @param payment_source [Hash] (optional) Similar to `capture`.
    # @return [Hash] The JSON response from PayPal containing authorization details.
    # @raise [Paypal::ApiError] If an error occurs.
    # @see [https://developer.paypal.com/docs/api/orders/v2/#orders_authorize](https://developer.paypal.com/docs/api/orders/v2/#orders_authorize) PayPal Orders Authorize API
    def authorize(order_id, paypal_request_id: SecureRandom.uuid, payment_source: nil)
      headers = { 'PayPal-Request-Id' => paypal_request_id }
      body_payload = {} # Initialize as empty hash
      body_payload[:payment_source] = payment_source if payment_source.present?

      Paypal.log(:info, "Authorizing PayPal order ID: #{order_id} with Request-Id: #{paypal_request_id}. Body: #{body_payload.to_json}")
      client.post("/v2/checkout/orders/#{order_id}/authorize", body: body_payload.empty? ? {} : body_payload, headers: headers)
    end

    # Updates details of an existing PayPal order (e.g., amount, items).
    # This operation can only be performed on orders with specific statuses (e.g., CREATED).
    # @param order_id [String] The PayPal order ID.
    # @param patch_operations [Array<Hash>] An array of patch operations according to JSON Patch standard.
    #   Example: `[{ op: 'replace', path: "/purchase_units/@reference_id=='default'/amount", value: { currency_code: 'USD', value: '12.00' } }]`
    # @return [Hash] Typically an empty response (HTTP 204 No Content) on success.
    # @raise [Paypal::ApiError] If an error occurs.
    # @see [https://developer.paypal.com/docs/api/orders/v2/#orders_patch](https://developer.paypal.com/docs/api/orders/v2/#orders_patch) PayPal Orders Patch API
    def update(order_id:, patch_operations:)
      Paypal.log(:info, "Patching PayPal order ID: #{order_id} with operations: #{patch_operations}")
      client.patch("/v2/checkout/orders/#{order_id}", body: patch_operations) # PATCH expects a body
    end
  end
end