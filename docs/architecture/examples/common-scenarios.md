# Common Scenarios

## Single-Tenant Operations (99% of use cases)

### Scenario 1: Create New Project
```ruby
# POST /api/v1/organizations/123/projects
# Middleware routes to shard_0 (123 % 3 = 0)

class ProjectsController < ApplicationController
  before_action :set_organization

  def create
    # @organization automatically loaded from correct shard
    @project = @organization.projects.build(project_params)

    if @project.save
      # Audit log goes to shared database
      log_audit('created_project', @project)
      # Feature usage tracking goes to shared database
      track_feature_usage('projects_created')

      render json: project_with_stats(@project), status: :created
    else
      render json: { errors: @project.errors }, status: :unprocessable_entity
    end
  end

  private

  def set_organization
    @organization = Organization.find(params[:organization_id])
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

# Database operations:
# 1. SELECT organizations.* FROM organizations WHERE id = 123 (shard_0)
# 2. INSERT INTO projects (organization_id, name, ...) VALUES (123, 'New Project', ...) (shard_0)
# 3. SELECT tasks.* FROM tasks WHERE project_id = ? (for stats calculation) (shard_0)
# 4. INSERT INTO audit_logs (organization_id, action, ...) VALUES (123, 'created_project', ...) (shared)
# 5. INSERT INTO feature_usage (organization_id, feature_name, ...) VALUES (123, 'projects_created', ...) (shared)
```

### Scenario 2: List Organization Users
```ruby
# GET /api/v1/organizations/456/users
# Middleware routes to shard_0 (456 % 3 = 0)

class UsersController < ApplicationController
  def index
    # All queries hit shard_0 only
    @users = @organization.users
                          .includes(:assigned_tasks)
                          .order(:name)

    track_feature_usage('users_listed')
    render json: @users.map { |u| user_with_task_count(u) }
  end

  private

  def user_with_task_count(user)
    user.as_json.merge(
      assigned_task_count: user.assigned_tasks.count
    )
  end
end

# Database operations (all on shard_0):
# 1. SELECT organizations.* FROM organizations WHERE id = 456
# 2. SELECT users.* FROM users WHERE organization_id = 456 ORDER BY name
# 3. SELECT tasks.* FROM tasks WHERE assigned_user_id IN (user_ids)
# 4. INSERT INTO feature_usage ... (shared database)
```

### Scenario 3: Update Task with Validation
```ruby
# PUT /api/v1/organizations/789/tasks/555
# Middleware routes to shard_0 (789 % 3 = 0)

class TasksController < ApplicationController
  before_action :set_task

  def update
    if @task.update(task_params)
      log_audit('updated_task', @task)
      render json: task_with_details(@task)
    else
      render json: { errors: @task.errors }, status: :unprocessable_entity
    end
  end

  private

  def set_task
    # All validation happens within single shard
    @task = @organization.tasks.find(params[:id])
  end

  def task_params
    params.require(:task).permit(:title, :description, :status, :assigned_user_id)
  end

  def task_with_details(task)
    task.as_json(include: {
      project: { only: [:id, :name] },
      assigned_user: { only: [:id, :name, :email] }
    })
  end
end

# Database operations (all on shard_0):
# 1. SELECT organizations.* FROM organizations WHERE id = 789
# 2. SELECT tasks.* FROM tasks WHERE organization_id = 789 AND id = 555
# 3. Validation queries (check assigned_user belongs to organization, etc.)
# 4. UPDATE tasks SET title = ?, status = ?, ... WHERE id = 555
# 5. SELECT projects.*, users.* FROM ... (for response serialization)
# 6. INSERT INTO audit_logs ... (shared database)
```

## Cross-Tenant Operations (1% of use cases)

### Scenario 4: Admin Dashboard Statistics
```ruby
# GET /api/v1/admin/organizations
# No middleware routing - queries ALL shards

class Admin::OrganizationsController < Admin::BaseController
  def index
    # Query all shards in parallel
    organizations = query_all_shards_parallel do
      Organization.all.map do |org|
        {
          id: org.id,
          name: org.name,
          plan_type: org.plan_type,
          user_count: org.users.count,
          project_count: org.projects.count,
          task_count: org.tasks.count,
          shard: current_shard_name
        }
      end
    end

    # Aggregate statistics
    total_stats = {
      total_organizations: organizations.count,
      total_users: organizations.sum { |o| o[:user_count] },
      total_projects: organizations.sum { |o| o[:project_count] },
      total_tasks: organizations.sum { |o| o[:task_count] },
      organizations_by_plan: organizations.group_by { |o| o[:plan_type] }
                                          .transform_values(&:count)
    }

    render json: {
      organizations: organizations,
      statistics: total_stats
    }
  end
end

# Database operations:
# Parallel queries to all shards:
# - shard_0: SELECT organizations.* FROM organizations
# - shard_0: SELECT COUNT(*) FROM users WHERE organization_id IN (...)
# - shard_1: SELECT organizations.* FROM organizations
# - shard_1: SELECT COUNT(*) FROM users WHERE organization_id IN (...)
# - shard_2: SELECT organizations.* FROM organizations
# - shard_2: SELECT COUNT(*) FROM users WHERE organization_id IN (...)
# Results aggregated in application layer
```

### Scenario 5: Platform-Wide Feature Usage Report
```ruby
# GET /api/v1/admin/feature_usage
# Queries shared database only

class Admin::FeatureUsageController < Admin::BaseController
  def index
    start_date = params[:start_date]&.to_date || 30.days.ago.to_date
    end_date = params[:end_date]&.to_date || Date.current

    # All data in shared database - single query
    usage_data = FeatureUsage.includes(:organization)
                            .where(date: start_date..end_date)

    # Group and aggregate
    feature_summary = usage_data.group(:feature_name).sum(:usage_count)
    daily_trends = usage_data.group(:date, :feature_name).sum(:usage_count)
    top_organizations = usage_data.joins("JOIN organizations ON organizations.id = feature_usage.organization_id")
                                 .group("organizations.name")
                                 .sum(:usage_count)
                                 .sort_by { |_, count| -count }
                                 .first(10)

    render json: {
      date_range: { start_date: start_date, end_date: end_date },
      feature_summary: feature_summary,
      daily_trends: daily_trends,
      top_organizations: top_organizations
    }
  end
end

# Database operations (shared database only):
# 1. SELECT feature_usage.*, organizations.name FROM feature_usage
#    JOIN organizations ON ... WHERE date BETWEEN ? AND ?
# 2. Application-level aggregation (no additional queries)
```

### Scenario 6: Find Organization by Name (Cross-Shard Search)
```ruby
# GET /api/v1/admin/organizations/search?name=TechCorp
# Must search ALL shards

class Admin::OrganizationsController < Admin::BaseController
  def search
    search_term = params[:name]
    return render json: { error: 'Name parameter required' } if search_term.blank?

    # Search all shards with timeout protection
    results = search_all_shards_with_timeout(timeout: 5.seconds) do
      Organization.where("name ILIKE ?", "%#{search_term}%").limit(10)
    end

    # Handle partial results due to timeout or shard failures
    successful_shards = results.count { |r| !r[:error] }
    total_shards = ShardRouter.all_shard_names.count

    organizations = results.reject { |r| r[:error] }
                          .flat_map { |r| r[:data] }

    render json: {
      organizations: organizations,
      search_metadata: {
        search_term: search_term,
        results_count: organizations.count,
        successful_shards: successful_shards,
        total_shards: total_shards,
        complete_search: successful_shards == total_shards
      }
    }
  end

  private

  def search_all_shards_with_timeout(timeout:)
    futures = ShardRouter.all_shard_names.map do |shard_name|
      Concurrent::Future.execute do
        ActiveRecord::Base.connected_to(shard: shard_name) do
          { shard: shard_name, data: yield, error: nil }
        end
      rescue StandardError => e
        { shard: shard_name, data: [], error: e.message }
      end
    end

    futures.map { |f| f.value(timeout) || { error: 'timeout' } }
  end
end

# Database operations:
# Parallel queries with timeout:
# - shard_0: SELECT * FROM organizations WHERE name ILIKE '%TechCorp%' LIMIT 10
# - shard_1: SELECT * FROM organizations WHERE name ILIKE '%TechCorp%' LIMIT 10
# - shard_2: SELECT * FROM organizations WHERE name ILIKE '%TechCorp%' LIMIT 10
# Results merged in application
```

## Background Job Scenarios

### Scenario 7: Process Organization Data (Single Shard)
```ruby
# Background job that processes data for one organization
class ProcessOrganizationDataJob < ApplicationJob
  def perform(organization_id, processing_type)
    shard_name = ShardRouter.shard_for_organization(organization_id)

    ActiveRecord::Base.connected_to(shard: shard_name) do
      organization = Organization.find(organization_id)

      case processing_type
      when 'monthly_report'
        generate_monthly_report(organization)
      when 'data_cleanup'
        cleanup_old_data(organization)
      when 'usage_analysis'
        analyze_usage_patterns(organization)
      end

      # Log completion
      AuditLog.log_action(
        organization: organization,
        action: "completed_#{processing_type}",
        resource: organization,
        metadata: { processed_at: Time.current }
      )
    end
  end

  private

  def generate_monthly_report(organization)
    # All queries hit single shard
    report_data = {
      users: organization.users.count,
      projects: organization.projects.count,
      tasks_completed: organization.tasks.where(status: 'done').count,
      active_users: organization.users.joins(:assigned_tasks)
                                    .where('tasks.updated_at > ?', 30.days.ago)
                                    .distinct.count
    }

    # Store report (could be in shared db or shard)
    OrganizationReport.create!(
      organization_id: organization.id,
      report_type: 'monthly',
      data: report_data,
      generated_at: Time.current
    )
  end
end
```

### Scenario 8: Platform Metrics Calculation (All Shards)
```ruby
# Background job that aggregates data from all shards
class PlatformMetricsJob < ApplicationJob
  def perform
    metrics = calculate_platform_metrics
    store_metrics(metrics)
    notify_stakeholders(metrics)
  end

  private

  def calculate_platform_metrics
    # Query all shards in parallel
    shard_data = ShardRouter.all_shard_names.map do |shard_name|
      Thread.new do
        ActiveRecord::Base.connected_to(shard: shard_name) do
          {
            shard: shard_name,
            organizations: Organization.count,
            users: User.count,
            projects: Project.count,
            tasks: Task.count,
            active_organizations: Organization.joins(:users)
                                            .where('users.updated_at > ?', 7.days.ago)
                                            .distinct.count
          }
        end
      rescue StandardError => e
        Rails.logger.error "Failed to collect metrics from #{shard_name}: #{e.message}"
        nil
      end
    end.map(&:value).compact

    # Aggregate results
    {
      total_organizations: shard_data.sum { |d| d[:organizations] },
      total_users: shard_data.sum { |d| d[:users] },
      total_projects: shard_data.sum { |d| d[:projects] },
      total_tasks: shard_data.sum { |d| d[:tasks] },
      active_organizations: shard_data.sum { |d| d[:active_organizations] },
      successful_shards: shard_data.count,
      total_shards: ShardRouter.all_shard_names.count,
      calculated_at: Time.current,
      shard_breakdown: shard_data
    }
  end

  def store_metrics(metrics)
    # Store in shared database
    ActiveRecord::Base.connected_to(database: { writing: :shared }) do
      PlatformMetric.create!(
        metric_type: 'daily_summary',
        data: metrics,
        calculated_at: metrics[:calculated_at]
      )
    end
  end
end
```

## Error Scenarios

### Scenario 9: Shard Unavailable
```ruby
# Request to organization on unavailable shard
# GET /api/v1/organizations/123/projects
# Organization 123 maps to shard_0, but shard_0 is down

# Middleware detects connection failure and returns:
{
  "error": {
    "code": "SHARD_OFFLINE",
    "message": "The organization data is temporarily unavailable",
    "shard": "shard_0",
    "timestamp": "2024-01-15T10:30:00Z"
  }
}

# HTTP Status: 503 Service Unavailable
```

### Scenario 10: Partial Cross-Shard Query Failure
```ruby
# Admin query where some shards fail
# GET /api/v1/admin/organizations

# If shard_1 is down, response includes partial results:
{
  "organizations": [
    # Organizations from shard_0 and shard_2 only
  ],
  "statistics": {
    "total_organizations": 150,  # Partial count
    "total_users": 2500         # Partial count
  },
  "query_metadata": {
    "successful_shards": 2,
    "total_shards": 3,
    "failed_shards": ["shard_1"],
    "data_completeness": 67
  }
}

# HTTP Status: 200 OK (partial success)
```

These scenarios demonstrate how the single-shard-per-request architecture keeps most operations simple while providing clear patterns for the few cases that require cross-shard coordination.