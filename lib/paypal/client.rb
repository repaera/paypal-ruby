module Paypal
  # Internal class responsible for making HTTP calls to the PayPal API.
  # Manages OAuth 2.0 authentication and basic response handling.
  class Client
    include HTTParty

    # @return [Paypal::Configuration] The current gem configuration.
    attr_reader :config
    # @return [String] The active OAuth 2.0 access token.
    attr_reader :access_token

    # Creates a new Client instance.
    # Automatically fetches an access token if one is not present or has expired.
    # @raise [Paypal::ConfigurationError] if essential configuration (client_id, client_secret, mode) is missing.
    # @raise [Paypal::AuthenticationError] if fetching the access token fails.
    def initialize
      @config = Paypal.current_configuration
      validate_configuration!

      self.class.base_uri @config.api_base_url
      @access_token_expires_at = Time.now - 1 # Force token fetch on first use
      @access_token = nil
      ensure_access_token
    end

    # @!visibility private
    # Returns default headers for API requests, including the Authorization Bearer token.
    # @return [Hash] Default HTTP headers.
    def default_headers
      ensure_access_token
      {
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{@access_token}"
      }
    end

    # Makes an HTTP POST request to the given PayPal API path.
    # @param path [String] The API path (e.g., '/v2/checkout/orders').
    # @param body [Hash] The request body (will be converted to JSON).
    # @param headers [Hash] Additional HTTP headers.
    # @return [Hash] The parsed JSON response from PayPal.
    # @raise [Paypal::ApiError] and its descendants if an API error occurs.
    def post(path, body: {}, headers: {})
      merged_headers = default_headers.merge(headers)
      Paypal.log(:debug, "POST to #{path} with body: #{body.to_json} and headers (auth omitted): #{loggable_headers(merged_headers)}")
      response = self.class.post(path, body: body.to_json, headers: merged_headers, timeout: 15) # Standard timeout
      handle_response(response)
    end

    # Makes an HTTP GET request to the given PayPal API path.
    # @param path [String] The API path.
    # @param query [Hash] Query parameters for the request.
    # @param headers [Hash] Additional HTTP headers.
    # @return [Hash] The parsed JSON response from PayPal.
    # @raise [Paypal::ApiError] and its descendants if an API error occurs.
    def get(path, query: {}, headers: {})
      merged_headers = default_headers.merge(headers)
      Paypal.log(:debug, "GET from #{path} with query: #{query} and headers (auth omitted): #{loggable_headers(merged_headers)}")
      response = self.class.get(path, query: query, headers: merged_headers, timeout: 15)
      handle_response(response)
    end

    # Makes an HTTP DELETE request to the given PayPal API path.
    # @param path [String] The API path.
    # @param headers [Hash] Additional HTTP headers.
    # @return [Hash] The parsed JSON response from PayPal (often empty for successful DELETE).
    # @raise [Paypal::ApiError] and its descendants if an API error occurs.
    def delete(path, headers: {})
      merged_headers = default_headers.merge(headers)
      Paypal.log(:debug, "DELETE to #{path} with headers (auth omitted): #{loggable_headers(merged_headers)}")
      response = self.class.delete(path, headers: merged_headers, timeout: 15)
      handle_response(response)
    end

    # Makes an HTTP PATCH request to the given PayPal API path.
    # @param path [String] The API path.
    # @param body [Hash] The request body (will be converted to JSON).
    # @param headers [Hash] Additional HTTP headers.
    # @return [Hash] The parsed JSON response from PayPal (often empty for successful PATCH).
    # @raise [Paypal::ApiError] and its descendants if an API error occurs.
    def patch(path, body: {}, headers: {})
      merged_headers = default_headers.merge(headers)
      Paypal.log(:debug, "PATCH to #{path} with body: #{body.to_json} and headers (auth omitted): #{loggable_headers(merged_headers)}")
      response = self.class.patch(path, body: body.to_json, headers: merged_headers, timeout: 15)
      handle_response(response)
    end

    private

    # @!visibility private
    # Returns a hash of headers suitable for logging (omits Authorization).
    # @param headers [Hash] The original headers.
    # @return [Hash] Headers with Authorization omitted.
    def loggable_headers(headers)
      headers.reject { |k, _v| k.casecmp('Authorization').zero? }
    end

    # @!visibility private
    def validate_configuration!
      raise Paypal::ConfigurationError, "PayPal client_id is not configured." if config.client_id.blank?
      raise Paypal::ConfigurationError, "PayPal client_secret is not configured." if config.client_secret.blank?
      raise Paypal::ConfigurationError, "PayPal mode is not configured (should be 'sandbox' or 'live')." unless ['sandbox', 'live'].include?(config.mode.to_s)
    end

    # @!visibility private
    # Ensures a valid access token is available, fetching a new one if necessary.
    def ensure_access_token
      return @access_token if @access_token && Time.now < @access_token_expires_at

      Paypal.log(:info, "Fetching new PayPal access token.")
      auth_response = self.class.post(
        '/v1/oauth2/token',
        headers: { 'Content-Type' => 'application/x-www-form-urlencoded', 'Accept' => 'application/json' },
        basic_auth: { username: config.client_id, password: config.client_secret },
        body: 'grant_type=client_credentials',
        timeout: 10 # Shorter timeout for token request
      )

      parsed_response = auth_response.parsed_response
      unless auth_response.success? && parsed_response.is_a?(Hash) && parsed_response['access_token']
        Paypal.log(:error, "Failed to fetch PayPal access token. Response: #{auth_response.code} - #{auth_response.body}")
        raise Paypal::AuthenticationError.new("Failed to authenticate with PayPal.", auth_response.code, auth_response.body)
      end

      @access_token = parsed_response['access_token']
      # expires_in is usually in seconds, add a small buffer (e.g., 5 minutes)
      @access_token_expires_at = Time.now + parsed_response['expires_in'].to_i - 300
      Paypal.log(:info, "Successfully fetched PayPal access token. Expires at: #{@access_token_expires_at}")
      @access_token
    end

    # @!visibility private
    # Handles the HTTP response from PayPal, raising an error if it's not successful.
    def handle_response(response)
      parsed_body = response.parsed_response.is_a?(Hash) ? response.parsed_response : {}
      paypal_debug_id = response.headers['paypal-debug-id']

      Paypal.log(:debug, "Response Code: #{response.code}, Body: #{response.body}, PayPal Debug ID: #{paypal_debug_id}")

      unless response.success?
        message = parsed_body['message'] || "PayPal API Error"
        if parsed_body['details'].is_a?(Array)
            details_messages = parsed_body['details'].map do |detail|
              field = detail['field'] ? detail['field'].gsub(%r{^/}, '') : (detail['issue'] || 'general')
              issue = detail['issue'] || detail['description'] # Payouts API sometimes uses 'description' in details
              description = detail['description']
              "#{field}: #{issue}#{" (#{description})" if description.present? && issue != description}"
            end.join('; ')
            message += " - Details: #{details_messages}" if details_messages.present?
        elsif parsed_body['name'] && parsed_body['message'] # Another common error format
            message = "#{parsed_body['name']}: #{parsed_body['message']}"
        end

        error_class = case response.code
                      when 400 then Paypal::BadRequestError
                      when 401 then Paypal::AuthenticationError # More specific for 401 if it's always token related
                      when 403 then Paypal::ForbiddenError
                      when 404 then Paypal::NotFoundError
                      when 422 then Paypal::UnprocessableEntityError
                      when 500..599 then Paypal::ServerError
                      else Paypal::ApiError
                      end

        # If the path indicates Payouts and it's a generic ApiError, use PayoutError
        if response.request&.path&.to_s&.include?('/v1/payments/payouts') && error_class == Paypal::ApiError
            error_class = Paypal::PayoutError
        end

        raise error_class.new(message, response.code, parsed_body, paypal_debug_id)
      end
      parsed_body # Return parsed body on success, or empty hash if body was nil/empty but successful (e.g. 204)
    end
  end
end