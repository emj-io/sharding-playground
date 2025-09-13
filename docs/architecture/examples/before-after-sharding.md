# Before & After Sharding

## Single Database vs Sharded Implementation

### Controller Implementation

#### Before: Single Database
```ruby
# app/controllers/projects_controller.rb (non-sharded)
class ProjectsController < ApplicationController
  before_action :set_organization
  before_action :set_project, only: [:show, :update, :destroy]

  def index
    @projects = @organization.projects.includes(:tasks)
    render json: @projects.map { |p| project_with_stats(p) }
  end

  def create
    @project = @organization.projects.build(project_params)

    if @project.save
      render json: project_with_stats(@project), status: :created
    else
      render json: { errors: @project.errors }, status: :unprocessable_entity
    end
  end

  private

  def set_organization
    @organization = Organization.find(params[:organization_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Organization not found" }, status: :not_found
  end

  def set_project
    @project = @organization.projects.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Project not found" }, status: :not_found
  end

  def project_params
    params.require(:project).permit(:name, :description, :status)
  end

  def project_with_stats(project)
    project.as_json.merge(
      task_count: project.task_count,
      completed_task_count: project.completed_task_count,
      progress_percentage: project.progress_percentage
    )
  end
end
```

#### After: Sharded (Single-Shard-Per-Request)
```ruby
# app/controllers/projects_controller.rb (sharded)
class ProjectsController < ApplicationController
  before_action :set_organization
  before_action :set_project, only: [:show, :update, :destroy]

  def index
    # Middleware has already routed to correct shard
    # This code is identical to non-sharded version!
    @projects = @organization.projects.includes(:tasks)
    track_feature_usage('projects_listed')
    render json: @projects
  end

  def create
    # Still identical - middleware handles sharding
    @project = @organization.projects.build(project_params)

    if @project.save
      log_audit('created_project', @project)
      track_feature_usage('projects_created')
      render json: @project, status: :created
    else
      render json: { errors: @project.errors }, status: :unprocessable_entity
    end
  end

  private

  def set_organization
    # This lookup automatically uses the correct shard
    @organization = Organization.find(params[:organization_id])
  end

  def set_project
    # This also uses the correct shard automatically
    @project = @organization.projects.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name, :description, :status)
  end

  # New: Helper methods for cross-tenant tracking
  def log_audit(action, resource)
    AuditLog.log_action(
      organization: @organization,
      action: action,
      resource: resource
    )
  end

  def track_feature_usage(feature_name)
    FeatureUsage.increment_usage(
      organization: @organization,
      feature_name: feature_name
    )
  end
end
```

**Key Point**: The business logic is identical! Sharding is transparent for single-tenant operations.

### Model Implementation

#### Before: Single Database
```ruby
# app/models/organization.rb (non-sharded)
class Organization < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :tasks, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :plan_type, presence: true, inclusion: { in: %w[free pro enterprise] }

  scope :by_plan, ->(plan) { where(plan_type: plan) }

  def user_count
    users.count
  end

  def project_count
    projects.count
  end

  def task_count
    tasks.count
  end

  def shard_key
    id  # Placeholder for future sharding
  end
end
```

#### After: Sharded
```ruby
# app/models/organization.rb (sharded)
class Organization < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :tasks, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :plan_type, inclusion: { in: %w[free pro enterprise] }

  # Business logic methods unchanged
  def user_count
    users.count
  end

  def project_count
    projects.count
  end

  # New: Shard-aware class methods for cross-tenant operations
  def self.all_with_stats
    # This method queries ALL shards
    ApplicationRecord.on_all_shards do
      Organization.all.map do |org|
        org.as_json.merge(
          user_count: org.user_count,
          project_count: org.project_count,
          task_count: org.tasks.count
        )
      end
    end
  end

  def self.total_count_across_shards
    ApplicationRecord.on_all_shards do
      Organization.count
    end.sum
  end
end
```

### Admin Controllers (New for Sharding)

#### Cross-Tenant Operations
```ruby
# app/controllers/admin/organizations_controller.rb (new for sharding)
class Admin::OrganizationsController < Admin::BaseController
  def index
    # This queries ALL shards and aggregates results
    @organizations = query_all_shards do
      Organization.all.map do |org|
        org.as_json.merge(
          shard: current_shard_name,
          user_count: org.user_count,
          project_count: org.project_count,
          task_count: org.tasks.count
        )
      end
    end

    # Platform-wide statistics
    total_stats = {
      total_organizations: @organizations.count,
      total_users: @organizations.sum { |org| org['user_count'] },
      total_projects: @organizations.sum { |org| org['project_count'] },
      total_tasks: @organizations.sum { |org| org['task_count'] }
    }

    render json: {
      organizations: @organizations,
      statistics: total_stats
    }
  end

  def show
    organization_id = params[:id].to_i
    shard_name = ShardRouter.shard_for_organization(organization_id)

    ActiveRecord::Base.connected_to(shard: shard_name) do
      @organization = Organization.find(organization_id)

      detailed_stats = {
        users: @organization.users.group(:role).count,
        projects: @organization.projects.group(:status).count,
        tasks: @organization.tasks.group(:status).count
      }

      render json: @organization.as_json.merge(
        shard: shard_name,
        detailed_stats: detailed_stats
      )
    end
  end
end
```

## Database Schema

### Before: Single Database
```sql
-- Single database schema
CREATE DATABASE myapp_development;

USE myapp_development;

CREATE TABLE organizations (
  id BIGINT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  plan_type VARCHAR(50) NOT NULL,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE users (
  id BIGINT PRIMARY KEY,
  organization_id BIGINT NOT NULL,
  email VARCHAR(255) NOT NULL,
  name VARCHAR(255) NOT NULL,
  role VARCHAR(50) NOT NULL,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  FOREIGN KEY (organization_id) REFERENCES organizations(id)
);

-- All tables in one database
```

### After: Sharded Database
```sql
-- Shard database schema (replicated across all shards)
CREATE DATABASE myapp_shard_0;
CREATE DATABASE myapp_shard_1;
CREATE DATABASE myapp_shard_2;

-- Each shard has identical schema
USE myapp_shard_0;

CREATE TABLE organizations (
  id BIGINT PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  plan_type VARCHAR(50) NOT NULL,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE users (
  id BIGINT PRIMARY KEY,
  organization_id BIGINT NOT NULL,
  email VARCHAR(255) NOT NULL,
  name VARCHAR(255) NOT NULL,
  role VARCHAR(50) NOT NULL,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  FOREIGN KEY (organization_id) REFERENCES organizations(id)
);

-- Plus shared database for cross-tenant data
CREATE DATABASE myapp_shared;

USE myapp_shared;

CREATE TABLE audit_logs (
  id BIGINT PRIMARY KEY,
  organization_id BIGINT NOT NULL,  -- Reference only, no FK
  user_id BIGINT,                   -- Reference only, no FK
  action VARCHAR(255) NOT NULL,
  resource_type VARCHAR(255) NOT NULL,
  resource_id BIGINT NOT NULL,
  metadata JSON,
  created_at TIMESTAMP
);
```

## Configuration Changes

### Before: Single Database
```yaml
# config/database.yml (non-sharded)
development:
  adapter: sqlite3
  database: db/development.sqlite3
  pool: 5
  timeout: 5000

test:
  adapter: sqlite3
  database: db/test.sqlite3
  pool: 5
  timeout: 5000
```

### After: Sharded
```yaml
# config/database.yml (sharded)
development:
  primary:
    adapter: sqlite3
    database: db/development.sqlite3
    pool: 5
    timeout: 5000

  shard_0:
    adapter: sqlite3
    database: db/development_shard_0.sqlite3
    pool: 5
    timeout: 5000

  shard_1:
    adapter: sqlite3
    database: db/development_shard_1.sqlite3
    pool: 5
    timeout: 5000

  shard_2:
    adapter: sqlite3
    database: db/development_shard_2.sqlite3
    pool: 5
    timeout: 5000

  shared:
    adapter: sqlite3
    database: db/development_shared.sqlite3
    pool: 5
    timeout: 5000
```

## Application Configuration

### Before: Standard Rails
```ruby
# config/application.rb (non-sharded)
module MyApp
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true
  end
end
```

### After: Sharding-Enabled
```ruby
# config/application.rb (sharded)
module MyApp
  class Application < Rails::Application
    config.load_defaults 8.0
    config.api_only = true

    # Add sharding middleware
    config.middleware.use ShardingMiddleware

    # Sharding configuration
    config.sharding = ActiveSupport::OrderedOptions.new
    config.sharding.shard_count = ENV.fetch('SHARD_COUNT', 3).to_i
  end
end
```

## Testing Changes

### Before: Simple Tests
```ruby
# spec/controllers/projects_controller_spec.rb (non-sharded)
RSpec.describe ProjectsController do
  let(:organization) { create(:organization) }

  describe 'GET #index' do
    it 'returns projects' do
      create_list(:project, 3, organization: organization)

      get :index, params: { organization_id: organization.id }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(3)
    end
  end
end
```

### After: Shard-Aware Tests
```ruby
# spec/controllers/projects_controller_spec.rb (sharded)
RSpec.describe ProjectsController do
  let(:organization) { create(:organization, id: 123) }
  let(:shard_name) { ShardRouter.shard_for_organization(123) }

  describe 'GET #index' do
    it 'returns projects from correct shard' do
      with_shard(shard_name) do
        organization.save!
        create_list(:project, 3, organization: organization)
      end

      get :index, params: { organization_id: organization.id }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(3)
    end
  end
end
```

## Summary of Changes

### What Stayed the Same
- **Business logic**: Core application functionality unchanged
- **Model relationships**: ActiveRecord associations work identically
- **Controller patterns**: Standard Rails patterns still apply
- **View rendering**: JSON responses identical

### What Changed
- **Infrastructure**: Multiple databases instead of one
- **Middleware**: Request routing based on organization ID
- **Admin features**: New cross-tenant operations
- **Configuration**: Database configuration for multiple shards
- **Testing**: Shard-aware test helpers and setup
- **Deployment**: Multiple databases to manage

### Developer Experience
- **Single-tenant operations**: No change in developer experience
- **Cross-tenant operations**: New, explicit admin controllers
- **Debugging**: Need to know which shard to examine
- **Testing**: Additional setup for shard management