# frozen_string_literal: true

require "test_helper"

class PaypalWebhookVerifierTest < Minitest::Test
  def setup
    stub_paypal_token_request # Needed because WebhookVerifier initializes a Client
    @verifier = Paypal::WebhookVerifier.new
    @base_url = Paypal.current_configuration.api_base_url

    @valid_headers = {
      auth_algo: "SHA256withRSA",
      cert_url: "[https://api.sandbox.paypal.com/v1/notifications/certs/CERT-ID-123](https://api.sandbox.paypal.com/v1/notifications/certs/CERT-ID-123)", # Example cert URL
      transmission_id: "trans_id_123",
      transmission_sig: "signature_abc",
      transmission_time: Time.now.utc.iso8601
    }
    @webhook_event_body_hash = { id: "EVENT_ID_123", event_type: "PAYMENT.CAPTURE.COMPLETED" }
    @webhook_event_body_json = @webhook_event_body_hash.to_json
  end

  def test_verify_signature_success
    expected_verify_payload = {
      auth_algo: @valid_headers[:auth_algo],
      cert_url: @valid_headers[:cert_url],
      transmission_id: @valid_headers[:transmission_id],
      transmission_sig: @valid_headers[:transmission_sig],
      transmission_time: @valid_headers[:transmission_time],
      webhook_id: Paypal.current_configuration.webhook_id,
      webhook_event: @webhook_event_body_hash # Parsed event body
    }
    stub_request(:post, "#{@base_url}/v1/notifications/verify-webhook-signature")
      .with(body: expected_verify_payload.to_json)
      .to_return(status: 200, body: json_fixture("webhook_verification_success").to_json, headers: { 'Content-Type' => 'application/json' })

    assert @verifier.verify_signature(
      auth_algo: @valid_headers[:auth_algo],
      cert_url: @valid_headers[:cert_url],
      transmission_id: @valid_headers[:transmission_id],
      transmission_sig: @valid_headers[:transmission_sig],
      transmission_time: @valid_headers[:transmission_time],
      webhook_event_body: @webhook_event_body_json
    )
  end

  def test_verify_signature_failure_from_paypal
    stub_request(:post, "#{@base_url}/v1/notifications/verify-webhook-signature")
      .to_return(status: 200, body: json_fixture("webhook_verification_failure").to_json, headers: { 'Content-Type' => 'application/json' })

    refute @verifier.verify_signature(
      auth_algo: @valid_headers[:auth_algo],
      cert_url: @valid_headers[:cert_url],
      transmission_id: @valid_headers[:transmission_id],
      transmission_sig: @valid_headers[:transmission_sig],
      transmission_time: @valid_headers[:transmission_time],
      webhook_event_body: @webhook_event_body_json
    )
  end

  def test_verify_signature_api_call_fails
    stub_request(:post, "#{@base_url}/v1/notifications/verify-webhook-signature")
      .to_return(status: 500, body: { message: "Internal Server Error" }.to_json, headers: { 'Content-Type' => 'application/json' })

    assert_raises Paypal::WebhookVerificationError do
      @verifier.verify_signature(
        auth_algo: @valid_headers[:auth_algo],
        cert_url: @valid_headers[:cert_url],
        transmission_id: @valid_headers[:transmission_id],
        transmission_sig: @valid_headers[:transmission_sig],
        transmission_time: @valid_headers[:transmission_time],
        webhook_event_body: @webhook_event_body_json
      )
    end
  end

  def test_verify_signature_missing_header
    refute @verifier.verify_signature(
      auth_algo: nil, # Missing header
      cert_url: @valid_headers[:cert_url],
      transmission_id: @valid_headers[:transmission_id],
      transmission_sig: @valid_headers[:transmission_sig],
      transmission_time: @valid_headers[:transmission_time],
      webhook_event_body: @webhook_event_body_json
    )
  end

  def test_verify_signature_invalid_json_body
     assert_raises Paypal::WebhookVerificationError do
      @verifier.verify_signature(
        auth_algo: @valid_headers[:auth_algo],
        cert_url: @valid_headers[:cert_url],
        transmission_id: @valid_headers[:transmission_id],
        transmission_sig: @valid_headers[:transmission_sig],
        transmission_time: @valid_headers[:transmission_time],
        webhook_event_body: "this is not json"
      )
    end
  end

  def test_webhook_id_not_configured_during_init
    original_webhook_id = Paypal.current_configuration.webhook_id
    Paypal.configure { |c| c.webhook_id = nil }
    assert_raises Paypal::ConfigurationError do
      Paypal::WebhookVerifier.new # Initialization will fail
    end
  ensure
    Paypal.configure { |c| c.webhook_id = original_webhook_id }
  end
end