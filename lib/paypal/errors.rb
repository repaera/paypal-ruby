module Paypal
  # Base error class for the Paypal gem.
  class Error < StandardError; end

  # Raised for configuration-related errors.
  class ConfigurationError < Error; end

  # Base class for API-related errors.
  # Includes details from the API response.
  class ApiError < Error
    # @return [Integer, nil] The HTTP response code.
    attr_reader :response_code
    # @return [Hash, String, nil] The parsed response body or raw body if parsing fails.
    attr_reader :response_body
    # @return [String, nil] The PayPal debug ID from response headers.
    attr_reader :paypal_debug_id

    # Initializes a new ApiError.
    # @param message [String] The error message.
    # @param response_code [Integer, nil] The HTTP status code.
    # @param response_body [Hash, String, nil] The response body.
    # @param paypal_debug_id [String, nil] The PayPal debug ID.
    def initialize(message, response_code = nil, response_body = nil, paypal_debug_id = nil)
      super(message)
      @response_code = response_code
      @response_body = response_body
      @paypal_debug_id = paypal_debug_id
    end

    # Provides a more detailed string representation of the error.
    # @return [String]
    def to_s
      base_message = super
      details = []
      details << "Code: #{response_code}" if response_code
      details << "PayPal Debug ID: #{paypal_debug_id}" if paypal_debug_id
      # Limit body preview to avoid overly long error messages
      body_preview = response_body.is_a?(String) ? response_body[0, 500] : response_body.inspect[0, 500]
      details << "Body: #{body_preview}" if response_body

      "#{base_message}#{" (#{details.join(', ')})" unless details.empty?}"
    end
  end

  # Raised for authentication failures (HTTP 401).
  class AuthenticationError < ApiError; end
  # Raised for invalid requests (HTTP 400).
  class BadRequestError < ApiError; end
  # Raised when access to a resource is forbidden (HTTP 401/403).
  # PayPal often uses 401 for token issues and 403 for permission issues.
  class UnauthorizedError < ApiError; end
  # Raised when access to a resource is forbidden (HTTP 403).
  class ForbiddenError < ApiError; end
  # Raised when a resource is not found (HTTP 404).
  class NotFoundError < ApiError; end
  # Raised for unprocessable entities (HTTP 422), often due to validation errors.
  class UnprocessableEntityError < ApiError; end
  # Raised for server-side errors at PayPal (HTTP 5xx).
  class ServerError < ApiError; end
  # Raised for webhook verification failures.
  class WebhookVerificationError < Error; end
  # Raised for errors specific to the Payouts API.
  class PayoutError < ApiError; end
end