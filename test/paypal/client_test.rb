# frozen_string_literal: true

require "test_helper"

class PaypalClientTest < Minitest::Test
  def setup
    # Call stub token for each test that might initialize a client
    stub_paypal_token_request
    @client = Paypal::Client.new
    @base_url = Paypal.current_configuration.api_base_url
  end

  def test_initializes_with_access_token
    assert_equal "TEST_ACCESS_TOKEN", @client.access_token
  end

  def test_get_request_success
    stub_request(:get, "#{@base_url}/v2/checkout/orders/TEST_ORDER_ID")
      .with(headers: { 'Authorization' => 'Bearer TEST_ACCESS_TOKEN' })
      .to_return(status: 200, body: { id: "TEST_ORDER_ID", status: "CREATED" }.to_json, headers: { 'Content-Type' => 'application/json' })

    response = @client.get("/v2/checkout/orders/TEST_ORDER_ID")
    assert_equal "TEST_ORDER_ID", response["id"]
  end

  def test_post_request_success
    payload = { intent: "CAPTURE", purchase_units: [{ amount: { currency_code: "USD", value: "10.00" } }] }
    stub_request(:post, "#{@base_url}/v2/checkout/orders")
      .with(
        body: payload.to_json,
        headers: { 'Authorization' => 'Bearer TEST_ACCESS_TOKEN', 'Content-Type' => 'application/json' }
      )
      .to_return(status: 201, body: { id: "NEW_ORDER_ID", status: "CREATED" }.to_json, headers: { 'Content-Type' => 'application/json' })

    response = @client.post("/v2/checkout/orders", body: payload)
    assert_equal "NEW_ORDER_ID", response["id"]
  end

  def test_api_error_raised_for_failed_request
    stub_request(:get, "#{@base_url}/v2/checkout/orders/INVALID_ID")
      .with(headers: { 'Authorization' => 'Bearer TEST_ACCESS_TOKEN' })
      .to_return(status: 404, body: json_fixture("resource_not_found_error").to_json, headers: { 'Content-Type' => 'application/json', 'paypal-debug-id' => 'debug_not_found_123' })

    error = assert_raises Paypal::NotFoundError do
      @client.get("/v2/checkout/orders/INVALID_ID")
    end
    assert_match "RESOURCE_NOT_FOUND", error.message
    assert_equal 404, error.response_code
    assert_equal "debug_not_found_123", error.paypal_debug_id
  end

  def test_authentication_error_if_token_fetch_fails
    # Override stub for token failure case
    WebMock.reset! # Clear previous stubs
    # Corrected: No markdown links in code
    token_url = "#{Paypal.current_configuration.api_base_url}/v1/oauth2/token"
    stub_request(:post, token_url)
      .to_return(status: 401, body: { error: "invalid_client", error_description: "Client Authentication failed" }.to_json)

    assert_raises Paypal::AuthenticationError do
      Paypal::Client.new # New initialization will attempt token fetch
    end
  end

  def test_configuration_error_if_client_id_missing
    original_client_id = Paypal.current_configuration.client_id
    Paypal.configure { |c| c.client_id = nil }
    assert_raises Paypal::ConfigurationError do
      Paypal::Client.new
    end
  ensure
    Paypal.configure { |c| c.client_id = original_client_id } # Restore configuration
  end

  def test_patch_request_success
    path = "/v1/some_resource/ID_TO_PATCH"
    payload = { status: "updated" }
    stub_request(:patch, "#{@base_url}#{path}")
      .with(body: payload.to_json, headers: { 'Authorization' => 'Bearer TEST_ACCESS_TOKEN' })
      .to_return(status: 200, body: { id: "ID_TO_PATCH", status: "updated" }.to_json, headers: { 'Content-Type' => 'application/json' })

    response = @client.patch(path, body: payload)
    assert_equal "updated", response["status"]
  end

  def test_delete_request_success
    path = "/v1/some_resource/ID_TO_DELETE"
    stub_request(:delete, "#{@base_url}#{path}")
      .with(headers: { 'Authorization' => 'Bearer TEST_ACCESS_TOKEN' })
      .to_return(status: 204, body: "", headers: { 'Content-Type' => 'application/json' }) # 204 No Content

    response = @client.delete(path)
    assert_empty response # Expect empty hash for 204 with no body
  end
end