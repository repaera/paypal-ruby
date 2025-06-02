# frozen_string_literal: true

require "test_helper"

class PaypalPayoutTest < Minitest::Test
  def setup
    stub_paypal_token_request
    @payout_service = Paypal::Payout.new
    @base_url = Paypal.current_configuration.api_base_url
  end

  def test_create_single_payout_success
    sender_item_id = "single_item_1"
    # Use hash_including for sender_batch_id because it's random
    stub_request(:post, "#{@base_url}/v1/payments/payouts")
      .with(body: hash_including(
        items: [hash_including(sender_item_id: sender_item_id)]
      ))
      .to_return(status: 201, body: json_fixture("payout_single_success").to_json, headers: { 'Content-Type' => 'application/json' })

    response = @payout_service.create_single(
      recipient_type: "EMAIL",
      receiver: "receiver@example.com",
      amount: "20.00",
      currency: "USD",
      note: "Test payout",
      sender_item_id: sender_item_id
    )
    assert_equal "PAYOUT_BATCH_SINGLE_123", response["batch_header"]["payout_batch_id"]
  end

  def test_create_batch_payout_success
    items = [
      { recipient_type: 'EMAIL', receiver: 'test1@example.com', amount: { value: '10.00', currency: 'USD' }, note: 'Note 1', sender_item_id: 'item1' },
      { recipient_type: 'PHONE', receiver: '1234567890', amount: { value: '15.00', currency: 'USD' }, note: 'Note 2', sender_item_id: 'item2' }
    ]
    custom_batch_id = "custom_batch_id_abc"
    expected_request_body_items = items.map do |item|
        {
          recipient_type: item[:recipient_type].upcase,
          receiver: item[:receiver],
          amount: {
            value: item[:amount][:value].to_s,
            currency: item[:amount][:currency].upcase
          },
          note: item[:note],
          sender_item_id: item[:sender_item_id]
        }
      end

    expected_request_body = {
      sender_batch_header: {
        sender_batch_id: custom_batch_id,
        email_subject: Paypal.current_configuration.payout_sender_batch_header_note,
        note: nil # If not set
      },
      items: expected_request_body_items
    }

    stub_request(:post, "#{@base_url}/v1/payments/payouts")
      .with(body: expected_request_body.to_json)
      .to_return(status: 201, body: json_fixture("payout_batch_success").to_json, headers: { 'Content-Type' => 'application/json' })

    response = @payout_service.create_batch(items: items, sender_batch_id: custom_batch_id)
    assert_equal custom_batch_id, response["batch_header"]["payout_batch_id"]
  end

  def test_show_batch_payout_success
    payout_batch_id = "BATCH_ID_SHOW_XYZ"
    stub_request(:get, "#{@base_url}/v1/payments/payouts/#{payout_batch_id}")
      .to_return(status: 200, body: json_fixture("payout_batch_show_success").to_json, headers: { 'Content-Type' => 'application/json' })

    response = @payout_service.show_batch(payout_batch_id)
    assert_equal "PROCESSING", response["batch_header"]["batch_status"]
  end

  def test_payout_api_validation_error_raised
    stub_request(:post, "#{@base_url}/v1/payments/payouts")
      .to_return(status: 400, body: json_fixture("payout_item_validation_error").to_json, headers: { 'Content-Type' => 'application/json' })

    error = assert_raises Paypal::PayoutError do # Use PayoutError
      @payout_service.create_single(
        recipient_type: "EMAIL", receiver: "r.com", amount: "1", currency: "USD", note: "n", sender_item_id: "s"
      )
    end
    assert_match "VALIDATION_ERROR", error.message
    assert_match "items[0].receiver: Required field not provided", error.message
  end

  def test_show_payout_item_success
    payout_item_id = "PAYOUT_ITEM_ID_123"
    # Create a fixture for this response, e.g., payout_item_show_success.json
    expected_response = { "payout_item_id" => payout_item_id, "transaction_status" => "SUCCESS" }.to_json
    stub_request(:get, "#{@base_url}/v1/payments/payouts-item/#{payout_item_id}")
      .to_return(status: 200, body: expected_response, headers: { 'Content-Type' => 'application/json' })

    response = @payout_service.show_item(payout_item_id)
    assert_equal "SUCCESS", response["transaction_status"]
  end

  def test_cancel_unclaimed_payout_item_success
    payout_item_id = "UNCLAIMED_ITEM_ID_456"
    # Create a fixture for this response, e.g., payout_item_cancel_success.json
    expected_response = { "payout_item_id" => payout_item_id, "transaction_status" => "RETURNED" }.to_json
    stub_request(:post, "#{@base_url}/v1/payments/payouts-item/#{payout_item_id}/cancel")
      .with(body: {}.to_json) # Empty body
      .to_return(status: 200, body: expected_response, headers: { 'Content-Type' => 'application/json' }) # Often 200 OK for cancel

    response = @payout_service.cancel_unclaimed_item(payout_item_id)
    assert_equal "RETURNED", response["transaction_status"]
  end
end