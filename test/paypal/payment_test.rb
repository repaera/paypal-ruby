# frozen_string_literal: true

require "test_helper"

class PaypalPaymentTest < Minitest::Test
  def setup
    stub_paypal_token_request
    @payment_service = Paypal::Payment.new
    @base_url = Paypal.current_configuration.api_base_url
  end

  def test_refund_capture_success
    capture_id = "CAPTURE_ID_FOR_REFUND"
    refund_amount = "10.00"
    currency = "USD"
    paypal_request_id = "refund_req_id_xyz"
    expected_request_body = { amount: { currency_code: currency, value: refund_amount } }

    stub_request(:post, "#{@base_url}/v2/payments/captures/#{capture_id}/refund")
      .with(
        body: expected_request_body.to_json,
        headers: { 'PayPal-Request-Id' => paypal_request_id }
      )
      .to_return(status: 201, body: json_fixture("refund_capture_success").to_json, headers: { 'Content-Type' => 'application/json' })

    response = @payment_service.refund_capture(
      capture_id,
      amount: refund_amount,
      currency_code: currency,
      paypal_request_id: paypal_request_id
    )
    assert_equal "REFUND_ID_123", response["id"]
    assert_equal "COMPLETED", response["status"]
  end

  def test_show_capture_success
    capture_id = "SHOW_CAPTURE_ABC"
    stub_request(:get, "#{@base_url}/v2/payments/captures/#{capture_id}")
      .to_return(status: 200, body: json_fixture("capture_show_success").to_json, headers: { 'Content-Type' => 'application/json' })

    response = @payment_service.show_capture(capture_id)
    assert_equal capture_id, response["id"]
    assert_equal "50.00", response["amount"]["value"]
  end

  def test_void_authorization_success
    authorization_id = "AUTH_ID_TO_VOID"
    # Void typically returns 204 No Content
    stub_request(:post, "#{@base_url}/v2/payments/authorizations/#{authorization_id}/void") # POST for void
      .with(body: {}.to_json) # Empty body for void
      .to_return(status: 204, body: "", headers: { 'Content-Type' => 'application/json' })

    response = @payment_service.void_authorization(authorization_id)
    assert_empty response # Expect empty hash for 204 with no body
  end

  def test_show_authorization_success
    auth_id = "AUTH_ID_SHOW_123"
    # Assuming a fixture for show_authorization_success.json exists or create one
    expected_response = { "id" => auth_id, "status" => "CREATED" }.to_json
    stub_request(:get, "#{@base_url}/v2/payments/authorizations/#{auth_id}")
      .to_return(status: 200, body: expected_response, headers: { 'Content-Type' => 'application/json' })

    response = @payment_service.show_authorization(auth_id)
    assert_equal auth_id, response["id"]
  end

  def test_capture_authorization_success
    auth_id = "AUTH_ID_CAPTURE_456"
    payload = { final_capture: true, amount: { currency_code: "USD", value: "50.00" } }
    # Assuming a fixture for capture_authorization_success.json exists
    expected_response = { "id" => "CAPTURE_FROM_AUTH_789", "status" => "COMPLETED" }.to_json
    stub_request(:post, "#{@base_url}/v2/payments/authorizations/#{auth_id}/capture")
      .with(body: payload.to_json)
      .to_return(status: 201, body: expected_response, headers: { 'Content-Type' => 'application/json' })

    response = @payment_service.capture_authorization(
      auth_id,
      amount: "50.00",
      currency_code: "USD",
      final_capture: true
    )
    assert_equal "CAPTURE_FROM_AUTH_789", response["id"]
  end
end