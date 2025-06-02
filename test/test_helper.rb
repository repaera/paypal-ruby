# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter "/test/" # Exclude test files from coverage report
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "paypal" # Load the gem

require "minitest/autorun"
require "webmock/minitest" # For stubbing HTTP requests

# Configure Paypal gem for tests
Paypal.configure do |config|
  config.client_id = "TEST_CLIENT_ID"
  config.client_secret = "TEST_CLIENT_SECRET"
  config.mode = "sandbox" # Ensures correct API base URL for stubs
  config.webhook_id = "TEST_WEBHOOK_ID"
  config.logger = Logger.new(nil) # Disable logging during tests or direct to a file
  config.payout_sender_batch_header_note = "Test Payout Note"
end

# Helper method to load JSON fixture files
# @param file_name [String] The name of the fixture file (without .json extension)
# @return [Hash] The parsed JSON data
def json_fixture(file_name)
  file_path = File.join(File.dirname(__FILE__), "fixtures", "#{file_name}.json")
  unless File.exist?(file_path)
    raise "Fixture file #{file_name}.json not found at #{file_path}. Please create it in test/fixtures/ directory."
  end
  JSON.parse(File.read(file_path))
end

# Helper method to stub the PayPal OAuth token request
# This is called before tests that involve API client initialization.
def stub_paypal_token_request
  # Corrected: No markdown links in code
  token_url = "#{Paypal.current_configuration.api_base_url}/v1/oauth2/token"
  stub_request(:post, token_url)
    .with(
      body: "grant_type=client_credentials",
      headers: {
        'Accept'=>'application/json', # HTTParty default Accept
        'Accept-Encoding'=>'gzip;q=1.0,deflate;q=0.6,identity;q=0.3', # HTTParty default
        'Authorization'=>'Basic VEVTVF9DTElFTlRfSUQ6VEVTVF9DTElFTlRfU0VDUkVU', # Base64("TEST_CLIENT_ID:TEST_CLIENT_SECRET")
        'Content-Type'=>'application/x-www-form-urlencoded',
        'User-Agent'=>'Ruby' # /\AHTTParty/ # Match HTTParty's User-Agent
      }
    )
    .to_return(
      status: 200,
      body: json_fixture("oauth_token_success").to_json, # Use a fixture for the token response
      headers: { 'Content-Type' => 'application/json' }
    )
    # .to_return(status: 200, body: "", headers: {})
end