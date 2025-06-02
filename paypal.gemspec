# frozen_string_literal: true

require_relative "lib/paypal/version"

Gem::Specification.new do |spec|
  spec.name = "paypal"
  spec.version = Paypal::VERSION
  spec.authors = ["Handy Wardhana"]
  spec.email = ["handy@repaera.com"]

  spec.summary = %q{PayPal REST API wrapper for Ruby, including Payouts and basic Marketplace features.}
  spec.description = <<~DESC
    Provides an easy-to-use Ruby client for interacting with the PayPal REST API.
    Supports creating orders (with platform fee splitting for marketplaces),
    payments, refunds, Payouts API (single and batch), and webhook verification.
    Designed for seamless integration with Ruby applications, including Ruby on Rails.
  DESC
  spec.homepage = "https://github.com/repaera/paypal-ruby"
  spec.license = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.required_ruby_version = Gem::Requirement.new(">= 2.7.0")

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
