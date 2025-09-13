# Rails Sharding Setup

## Core Principle: One Shard Per Request

Every HTTP request, background job, and Rack request should be served by exactly one shard. This keeps the developer experience simple and ensures predictable performance.

## Implementation Components

### 1. Shard Router
```ruby
# app/lib/shard_router.rb
class ShardRouter
  SHARD_COUNT = ENV.fetch('SHARD_COUNT', 3).to_i

  def self.shard_for_organization(organization_id)
    shard_number = organization_id.to_i % SHARD_COUNT
    "shard_#{shard_number}".to_sym
  end

  def self.all_shard_names
    (0...SHARD_COUNT).map { |i| "shard_#{i}".to_sym }
  end

  def self.organization_id_from_request(request)
    # Extract from URL: /api/v1/organizations/123/projects
    if request.path.match(%r{/organizations/(\d+)})
      $1.to_i
    end
  end
end
```

### 2. Sharding Middleware
```ruby
# app/middleware/sharding_middleware.rb
class ShardingMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    organization_id = ShardRouter.organization_id_from_request(request)

    if organization_id
      shard_name = ShardRouter.shard_for_organization(organization_id)

      # Set shard context for the entire request
      ActiveRecord::Base.connected_to(shard: shard_name) do
        @app.call(env)
      end
    else
      # No organization context (health checks, admin endpoints, etc.)
      @app.call(env)
    end
  end
end
```

### 3. Database Configuration
```yaml
# config/database.yml
default: &default
  adapter: sqlite3
  pool: <%= ENV.fetch("RAILS_MAX_THREADS") { 5 } %>
  timeout: 5000

development:
  primary:
    <<: *default
    database: db/development.sqlite3

  # Tenant shard databases
  shard_0:
    <<: *default
    database: db/development_shard_0.sqlite3

  shard_1:
    <<: *default
    database: db/development_shard_1.sqlite3

  shard_2:
    <<: *default
    database: db/development_shard_2.sqlite3

  # Shared database for cross-tenant data
  shared:
    <<: *default
    database: db/development_shared.sqlite3

test:
  primary:
    <<: *default
    database: db/test.sqlite3

  shard_0:
    <<: *default
    database: db/test_shard_0.sqlite3

  shard_1:
    <<: *default
    database: db/test_shard_1.sqlite3

  shard_2:
    <<: *default
    database: db/test_shard_2.sqlite3

  shared:
    <<: *default
    database: db/test_shared.sqlite3
```

### 4. Model Configuration
```ruby
# app/models/application_record.rb
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Helper for cross-shard operations (rare)
  def self.on_all_shards(&block)
    results = []
    ShardRouter.all_shard_names.each do |shard_name|
      ActiveRecord::Base.connected_to(shard: shard_name) do
        results << block.call
      end
    end
    results.flatten
  end
end

# Tenant-scoped models (live on shards)
class Organization < ApplicationRecord
  has_many :users
  has_many :projects
  has_many :tasks
end

class User < ApplicationRecord
  belongs_to :organization
  has_many :assigned_tasks, class_name: 'Task'
end

# Cross-tenant models (live on shared database)
class AuditLog < ApplicationRecord
  connects_to database: { writing: :shared, reading: :shared }

  validates :organization_id, presence: true
end

class FeatureUsage < ApplicationRecord
  connects_to database: { writing: :shared, reading: :shared }

  validates :organization_id, presence: true
end
```

### 5. Controller Implementation
```ruby
# app/controllers/application_controller.rb
class ApplicationController < ActionController::API
  before_action :set_organization, if: :organization_required?

  private

  def set_organization
    org_id = params[:organization_id]
    raise "Organization ID required" unless org_id

    # This will automatically use the correct shard due to middleware
    @organization = Organization.find(org_id)
  end

  def organization_required?
    # Most endpoints require organization context
    !request.path.start_with?('/health', '/admin')
  end
end

# Regular tenant-scoped controller
class ProjectsController < ApplicationController
  def index
    # This automatically queries the correct shard
    @projects = @organization.projects.includes(:tasks)
    render json: @projects
  end

  def create
    # This automatically creates in the correct shard
    @project = @organization.projects.create!(project_params)
    render json: @project, status: :created
  end

  private

  def project_params
    params.require(:project).permit(:name, :description, :status)
  end
end
```

### 6. Cross-Tenant Admin Controllers
```ruby
# app/controllers/admin/base_controller.rb
class Admin::BaseController < ApplicationController
  # Skip organization requirement for admin endpoints
  skip_before_action :set_organization

  private

  def query_all_shards(&block)
    results = []
    ShardRouter.all_shard_names.each do |shard_name|
      begin
        ActiveRecord::Base.connected_to(shard: shard_name) do
          results.concat(Array(block.call))
        end
      rescue StandardError => e
        Rails.logger.error "Failed to query #{shard_name}: #{e.message}"
      end
    end
    results
  end
end

# app/controllers/admin/organizations_controller.rb
class Admin::OrganizationsController < Admin::BaseController
  def index
    # This queries ALL shards
    @organizations = query_all_shards do
      Organization.all.map do |org|
        org.as_json.merge(
          user_count: org.users.count,
          project_count: org.projects.count,
          task_count: org.tasks.count
        )
      end
    end

    render json: { organizations: @organizations }
  end
end
```

## Routing Setup

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Health check (no shard required)
  get "up" => "rails/health#show"
  get "health/shards" => "health#shards"

  namespace :api do
    namespace :v1 do
      # Organization-scoped routes (single shard per request)
      resources :organizations, only: [] do
        resources :users
        resources :projects do
          resources :tasks
        end
        resources :tasks  # Direct access to organization tasks
      end

      # Cross-tenant admin routes (query multiple shards)
      namespace :admin do
        resources :organizations, only: [:index, :show]
        resources :audit_logs, only: [:index]
        resources :feature_usage, only: [:index]
      end
    end
  end
end
```

## Background Jobs
```ruby
# Ensure jobs also use single shard
class OrganizationJob < ApplicationJob
  def perform(organization_id)
    shard_name = ShardRouter.shard_for_organization(organization_id)

    ActiveRecord::Base.connected_to(shard: shard_name) do
      organization = Organization.find(organization_id)
      # Job logic here - all data access uses correct shard
      process_organization_data(organization)
    end
  end
end

# Cross-tenant background jobs
class PlatformMetricsJob < ApplicationJob
  def perform
    metrics = {}

    ShardRouter.all_shard_names.each do |shard_name|
      ActiveRecord::Base.connected_to(shard: shard_name) do
        metrics[shard_name] = {
          organization_count: Organization.count,
          user_count: User.count,
          project_count: Project.count
        }
      end
    end

    # Store aggregated metrics in shared database
    ActiveRecord::Base.connected_to(database: { writing: :shared }) do
      PlatformMetric.create!(
        data: metrics,
        calculated_at: Time.current
      )
    end
  end
end
```

## Application Configuration
```ruby
# config/application.rb
module ShardingTestApi
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true

    # Add sharding middleware
    config.middleware.use ShardingMiddleware

    # Shard configuration
    config.sharding = ActiveSupport::OrderedOptions.new
    config.sharding.shard_count = ENV.fetch('SHARD_COUNT', 3).to_i
  end
end
```

## Development Setup

### Database Creation
```ruby
# lib/tasks/sharding.rake
namespace :db do
  namespace :sharding do
    desc "Create all shard databases"
    task create: :environment do
      ShardRouter.all_shard_names.each do |shard_name|
        puts "Creating #{shard_name}..."
        ActiveRecord::Base.connected_to(shard: shard_name) do
          ActiveRecord::Tasks::DatabaseTasks.create_current
        end
      end

      # Create shared database
      ActiveRecord::Base.connected_to(database: { writing: :shared }) do
        ActiveRecord::Tasks::DatabaseTasks.create_current('shared')
      end
    end

    desc "Migrate all shards"
    task migrate: :environment do
      ShardRouter.all_shard_names.each do |shard_name|
        puts "Migrating #{shard_name}..."
        ActiveRecord::Base.connected_to(shard: shard_name) do
          ActiveRecord::Base.connection.migration_context.migrate
        end
      end

      # Migrate shared database
      ActiveRecord::Base.connected_to(database: { writing: :shared }) do
        ActiveRecord::Base.connection.migration_context.migrate
      end
    end

    desc "Seed all shards"
    task seed: :environment do
      ShardRouter.all_shard_names.each do |shard_name|
        puts "Seeding #{shard_name}..."
        ActiveRecord::Base.connected_to(shard: shard_name) do
          Rails.application.load_seed
        end
      end
    end
  end
end
```

### Development Commands
```bash
# Setup all databases
rails db:sharding:create
rails db:sharding:migrate
rails db:sharding:seed

# Or use shortcut
rails db:setup:sharding  # (custom task that runs all three)
```

## Testing Setup
```ruby
# spec/support/sharding_helpers.rb
module ShardingHelpers
  def with_shard(shard_name)
    ActiveRecord::Base.connected_to(shard: shard_name) do
      yield
    end
  end

  def clean_all_shards
    ShardRouter.all_shard_names.each do |shard_name|
      with_shard(shard_name) do
        DatabaseCleaner.clean
      end
    end

    # Clean shared database
    ActiveRecord::Base.connected_to(database: { writing: :shared }) do
      DatabaseCleaner.clean
    end
  end
end

# spec/rails_helper.rb
RSpec.configure do |config|
  config.include ShardingHelpers

  config.before(:each) do
    clean_all_shards
  end
end
```

## Key Benefits

### For Developers
- **No sharding logic in business code**: Controllers and models look normal
- **Automatic routing**: Framework handles shard selection
- **Clear boundaries**: Cross-tenant operations are explicit

### For Operations
- **Predictable performance**: Each request hits exactly one database
- **Simple monitoring**: Can track performance per shard
- **Isolated failures**: Problems in one shard don't affect others

### For Scaling
- **Linear scaling**: Add more shards as you grow
- **Easy tenant isolation**: Each tenant completely separate
- **Simple backup/restore**: Can backup individual tenants

## Next Steps
- [Connection Management](./connection-management.md) - Managing database connections efficiently
- [Middleware & Routing](./middleware-routing.md) - Deep dive into request routing
- [Testing Strategies](./testing-strategies.md) - Testing sharded applications