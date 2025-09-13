# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories.
Dir[Rails.root.join('spec', 'support', '**', '*.rb')].sort.each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  # Include FactoryBot methods
  config.include FactoryBot::Syntax::Methods

  # Use transactional fixtures
  config.use_transactional_fixtures = true

  # RSpec Rails can automatically mix in different behaviours to your tests
  # based on their file location, for example enabling you to call `get` and
  # `post` in specs under `spec/controllers`.
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!

  # Database cleaner configuration for sharding
  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:each) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.start

    # Also clean shard databases
    shard_count = Rails.application.config.sharding.shard_count
    (0...shard_count).each do |shard_number|
      shard_name = "shard_#{shard_number}".to_sym
      begin
        ActiveRecord::Base.connected_to(shard: shard_name) do
          DatabaseCleaner.start
        end
      rescue ActiveRecord::DatabaseConnectionError
        # Shard may not be available in test environment
      end
    end
  end

  config.after(:each) do
    DatabaseCleaner.clean

    # Also clean shard databases
    shard_count = Rails.application.config.sharding.shard_count
    (0...shard_count).each do |shard_number|
      shard_name = "shard_#{shard_number}".to_sym
      begin
        ActiveRecord::Base.connected_to(shard: shard_name) do
          DatabaseCleaner.clean
        end
      rescue ActiveRecord::DatabaseConnectionError
        # Shard may not be available in test environment
      end
    end
  end
end

# Shoulda Matchers configuration
Shoulda::Matchers.configure do |config|
  config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end