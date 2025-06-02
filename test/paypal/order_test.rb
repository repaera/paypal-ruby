# frozen_string_literal: true

require "test_helper"

class PaypalOrderTest < Minitest::Test
  def setup
    stub_paypal_token_request # Ensure token is always stubbed
    @order_service = Paypal::Order.new
    @base_url = Paypal.current_configuration.api_base_url
  end

  def test_create_order_success
    payload = {
      intent: "CAPTURE",
      purchase_units: [{ amount: { currency_code: "USD", value: "100.00" } }]
    }
    # Use fixture for expected response
    stub_request(:post, "#{@base_url}/v2/checkout/orders")
      .with(body: payload.to_json)
      .to_return(status: 201, body: json_fixture("order_created_success").to_json, headers: { 'Content-Type' => 'application/json' })

    response = @order_service.create(intent: "CAPTURE", purchase_units: [{ amount: { currency_code: "USD", value: "100.00" } }])
    assert_equal "ORDER_CREATED_123", response["id"]
    # Corrected: No markdown links in code
    expected_approval_url = "https://www.sandbox.paypal.com/checkoutnow?token=ORDER_CREATED_123"
    assert_equal expected_approval_url, response["links"].find { |l| l["rel"] == "approve" }["href"]
  end

  def test_create_order_with_platform_fees_marketplace
    customer_pays = 100.00
    platform_fee_amount = 10.00
    currency = 'USD'
    tasker_merchant_id = 'TASKER_MERCHANT_ID_123'

    payment_source_payload = {
      paypal: {
        experience_context: { return_url: "return.com", cancel_url: "cancel.com" },
        payment_instruction: {
          platform_fees: [{ amount: { currency_code: currency, value: platform_fee_amount.to_s } }],
          disbursement_mode: 'INSTANT'
        }
      }
    }
    purchase_units = [{
      amount: { currency_code: currency, value: customer_pays.to_s },
      payee: { merchant_id: tasker_merchant_id }
    }]

    expected_request_body = {
      intent: "CAPTURE",
      purchase_units: purchase_units,
      payment_source: payment_source_payload
    }

    stub_request(:post, "#{@base_url}/v2/checkout/orders")
      .with(body: expected_request_body.to_json)
      .to_return(status: 201, body: json_fixture("order_marketplace_created_success").to_json, headers: { 'Content-Type' => 'application/json' })

    response = @order_service.create(
      intent: "CAPTURE",
      purchase_units: purchase_units,
      payment_source: payment_source_payload
    )
    assert_equal "ORDER_MARKETPLACE_123", response["id"]
  end

  def test_show_order_success
    order_id = "ORDER_SHOW_456"
    stub_request(:get, "#{@base_url}/v2/checkout/orders/#{order_id}")
      .to_return(status: 200, body: json_fixture("order_show_success").to_json, headers: { 'Content-Type' => 'application/json' })

    response = @order_service.show(order_id)
    assert_equal order_id, response["id"]
    assert_equal "APPROVED", response["status"]
  end

  def test_capture_order_success
    order_id = "ORDER_CAPTURE_789"
    paypal_request_id = "capture_req_id_123"

    stub_request(:post, "#{@base_url}/v2/checkout/orders/#{order_id}/capture")
      .with(
        headers: { 'PayPal-Request-Id' => paypal_request_id },
        body: {}.to_json # Empty body if no payment_source
      )
      .to_return(status: 201, body: json_fixture("order_capture_success").to_json, headers: { 'Content-Type' => 'application/json' })

    response = @order_service.capture(order_id, paypal_request_id: paypal_request_id)
    assert_equal "COMPLETED", response["status"]
    assert_equal "CAPTURE_ID_ABC", response["purchase_units"].first["payments"]["captures"].first["id"]
  end

  def test_capture_order_already_captured_error
    order_id = "ORDER_ALREADY_CAPTURED"
    stub_request(:post, "#{@base_url}/v2/checkout/orders/#{order_id}/capture")
      .to_return(status: 422, body: json_fixture("order_capture_error_422").to_json, headers: { 'Content-Type' => 'application/json', 'paypal-debug-id' => 'debug_capture_error_422' })

    error = assert_raises Paypal::UnprocessableEntityError do
      @order_service.capture(order_id)
    end

    assert_match "ORDER_ALREADY_CAPTURED", error.message
    assert_equal "debug_capture_error_422", error.paypal_debug_id
  end

  def test_update_order_success
    order_id = "ORDER_TO_UPDATE_123"
    patch_operations = [{ op: 'replace', path: "/purchase_units/@reference_id=='default'/amount", value: { currency_code: 'USD', value: '12.00' } }]

    stub_request(:patch, "#{@base_url}/v2/checkout/orders/#{order_id}")
      .with(body: patch_operations.to_json)
      .to_return(status: 204, body: "", headers: { 'Content-Type' => 'application/json' }) # 204 No Content

    response = @order_service.update(order_id: order_id, patch_operations: patch_operations)
    assert_empty response # Expect empty hash for 204
  end
end