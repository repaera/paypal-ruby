# frozen_string_literal: true

# require "bundler/gem_tasks"
# require "minitest/test_task"

# Minitest::TestTask.create

# require "rubocop/rake_task"

# RuboCop::RakeTask.new

# task default: %i[test rubocop]

require "bundler/gem_tasks"
require "rake/testtask"
require "yard" # For documentation tasks
require "rubocop/rake_task" # For RuboCop task

# Run lint and tests as the default rake task
task default: [:rubocop, :test]

# Task to run RuboCop
RuboCop::RakeTask.new(:rubocop) do |task|
  task.fail_on_error = true # Fail build if RuboCop errors exist
  # task.patterns = ['lib/**/*.rb', 'test/**/*.rb', 'paypal.gemspec', 'Rakefile'] # Be more specific if needed
end

# Task to run Minitest tests
Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.pattern = "test/**/*_test.rb"
  t.verbose = true
end

# Task to generate YARD documentation
YARD::Rake::YardocTask.new(:doc) do |t|
  t.files   = ['lib/**/*.rb', 'README.md']
  t.options = [
    '--output-dir', 'doc',
    '--title', 'PayPal Gem Documentation',
    '--readme', 'README.md'
  ]
end

# Task to clean generated files
task :clean do
  system("rm -rf pkg coverage doc .yardoc *.gem")
  puts "Cleaned generated files."
end

# Task to build the gem
task build: :clean do
  # Ensure version is correct before build
  system("gem build #{Dir.glob('*.gemspec').first}")
  puts "Gem built."
end

# Task to install the gem locally
task install: :build do
  # Dynamically get gem name and version for install command
  gem_name = Gem.loaded_specs['paypal']&.name || 'paypal' # Fallback to 'paypal'
  gem_version = Paypal::VERSION
  system("gem install ./pkg/#{gem_name}-#{gem_version}.gem")
  puts "Gem installed locally."
end

# Task to release the gem to RubyGems.org
task :release_manual do
  puts "This task is for manual release. CI/CD handles release on tag push."
  puts "Ensure version is bumped and all changes are committed."
  puts "Continue with manual release? (y/n)"
  abort("Manual release cancelled.") unless STDIN.gets.chomp.downcase == 'y'

  gem_name = Gem.loaded_specs['paypal']&.name || 'paypal'
  gem_version = Paypal::VERSION
  # Ensure gem is built
  Rake::Task['build'].invoke unless File.exist?("pkg/#{gem_name}-#{gem_version}.gem")

  system("gem push pkg/#{gem_name}-#{gem_version}.gem")
  puts "Gem manually released to RubyGems.org."
end

# Alias for common tasks
task ci: [:rubocop, :test, :doc]

desc "Run RuboCop linter"
task lint: :rubocop

desc "Run all tests"
task spec: :test # Alias for those used to rspec

desc "Generate YARD documentation"
task yard: :doc
