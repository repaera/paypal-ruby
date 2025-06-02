# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "active_support/configurable"
require "httparty"
require "json"
require "logger"
require "securerandom"

# Paths updated to reflect new directory structure
require_relative "paypal/version"
require_relative "paypal/errors"
require_relative "paypal/client"
require_relative "paypal/order"
require_relative "paypal/payment"
require_relative "paypal/webhook_verifier"
require_relative "paypal/payout"

# Main module for interacting with the PayPal API.
# Provides configuration and services for various PayPal functionalities.
module Paypal
  include ActiveSupport::Configurable

  # @!attribute client_id
  #   @return [String] Your PayPal Client ID.
  # @!attribute client_secret
  #   @return [String] Your PayPal Client Secret.
  # @!attribute mode
  #   @return [String] API operation mode ('sandbox' or 'live').
  # @!attribute webhook_id
  #   @return [String] Your Webhook ID from PayPal Developer Dashboard (for webhook verification).
  # @!attribute api_base_url
  #   @return [String] Base URL for the PayPal API (automatically set based on mode).
  # @!attribute logger
  #   @return [Logger] Logger instance used by the gem (default: Rails.logger or Logger.new($stdout)).
  # @!attribute payout_sender_batch_header_note
  #   @return [String] Default note for the email subject or batch header when making Payouts.
  config_accessor :client_id, :client_secret, :mode, :webhook_id, :api_base_url, :logger, :payout_sender_batch_header_note

  # Configures the Paypal gem.
  # Should be called once, typically in an initializer.
  #
  # @example
  #   Paypal.configure do |config|
  #     config.client_id = ENV['PAYPAL_CLIENT_ID']
  #     config.client_secret = ENV['PAYPAL_CLIENT_SECRET']
  #     config.mode = 'sandbox'
  #     config.webhook_id = ENV['PAYPAL_WEBHOOK_ID']
  #   end
  # @yield [config] Gives access to the configuration object.
  # @yieldparam config [Paypal::Configuration] The configuration object.
  # @return [void]
  def self.configure
    yield(config)
    config.api_base_url = config.mode.to_s == 'live' ?
                            'api-m.paypal.com' :
                            'api-m.sandbox.paypal.com'
    # Ensure logger is initialized if not set by user
    config.logger ||= defined?(Rails) && Rails.logger ? Rails.logger : Logger.new($stdout)
    config.payout_sender_batch_header_note ||= "Your Payout from Our Platform" # Default note
  end

  # Returns the current configuration object.
  # @return [Paypal::Configuration] The configuration object.
  def self.current_configuration
    config
  end

  # Logs a message using the configured logger.
  # @param level [Symbol] The log level (e.g., :info, :debug, :error).
  # @param message [String] The message to log.
  # @return [void]
  def self.log(level, message)
    # Ensure logger is available even if configure hasn't been explicitly called yet with a logger
    current_logger = config.logger || (defined?(Rails) && Rails.logger ? Rails.logger : Logger.new($stdout))
    current_logger&.send(level, "[PaypalGem] #{message}") # Logging tag
  end
end