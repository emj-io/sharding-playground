# Rails Application Structure for Sharding

## Current Application Models

Our test application has been designed with sharding in mind, even though sharding is not yet implemented. Here's how the models are structured:

### Core Models

#### Organization (Shard Key Entity)
```ruby
class Organization < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :projects, dependent: :destroy
  has_many :tasks, dependent: :destroy

  validates :name, presence: true, uniqueness: true
  validates :plan_type, presence: true, inclusion: { in: %w[free pro enterprise] }

  scope :by_plan, ->(plan) { where(plan_type: plan) }

  def shard_key
    id  # This will be used for shard routing
  end

  def user_count
    users.count
  end

  def project_count
    projects.count
  end

  def task_count
    tasks.count
  end
end
```

#### Project (Tenant-Scoped)
```ruby
class Project < ApplicationRecord
  belongs_to :organization
  has_many :tasks, dependent: :destroy

  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: %w[active archived completed] }
  validates :name, uniqueness: { scope: :organization_id }

  scope :active, -> { where(status: 'active') }
  scope :archived, -> { where(status: 'archived') }
  scope :completed, -> { where(status: 'completed') }

  def task_count
    tasks.count
  end

  def completed_task_count
    tasks.where(status: 'done').count
  end

  def pending_task_count
    tasks.where(status: ['todo', 'in_progress']).count
  end

  def progress_percentage
    return 0 if task_count.zero?
    (completed_task_count.to_f / task_count * 100).round(2)
  end
end
```

#### Task (Tenant-Scoped)
```ruby
class Task < ApplicationRecord
  belongs_to :project
  belongs_to :organization
  belongs_to :assigned_user, class_name: 'User', optional: true

  validates :title, presence: true
  validates :status, presence: true, inclusion: { in: %w[todo in_progress done] }
  validates :priority, presence: true, inclusion: { in: %w[low medium high] }

  scope :todo, -> { where(status: 'todo') }
  scope :in_progress, -> { where(status: 'in_progress') }
  scope :done, -> { where(status: 'done') }
  scope :high_priority, -> { where(priority: 'high') }
  scope :due_today, -> { where(due_date: Date.current) }
  scope :overdue, -> { where('due_date < ?', Date.current) }

  def completed?
    status == 'done'
  end

  def overdue?
    due_date && due_date < Date.current && !completed?
  end

  def assigned?
    assigned_user.present?
  end
end
```

#### User (Tenant-Scoped)
```ruby
class User < ApplicationRecord
  belongs_to :organization
  has_many :assigned_tasks, class_name: 'Task', foreign_key: 'assigned_user_id'

  validates :email, presence: true, uniqueness: { scope: :organization_id }
  validates :name, presence: true
  validates :role, presence: true, inclusion: { in: %w[admin member viewer] }

  scope :admins, -> { where(role: 'admin') }
  scope :members, -> { where(role: 'member') }
  scope :viewers, -> { where(role: 'viewer') }

  def admin?
    role == 'admin'
  end

  def can_edit?
    %w[admin member].include?(role)
  end

  def active_task_count
    assigned_tasks.where(status: ['todo', 'in_progress']).count
  end

  def completed_task_count
    assigned_tasks.where(status: 'done').count
  end
end
```

### Cross-Tenant Models (Shared Database)

#### AuditLog
```ruby
class AuditLog < ApplicationRecord
  # This will live in the shared database for cross-tenant tracking
  validates :organization_id, presence: true
  validates :action, presence: true
  validates :resource_type, presence: true
  validates :resource_id, presence: true

  scope :for_organization, ->(org_id) { where(organization_id: org_id) }
  scope :recent, -> { order(created_at: :desc) }

  def self.log_action(organization:, action:, resource:, user: nil, metadata: {})
    create!(
      organization_id: organization.id,
      user_id: user&.id,
      action: action,
      resource_type: resource.class.name,
      resource_id: resource.id,
      metadata: metadata
    )
  end
end
```

#### FeatureUsage
```ruby
class FeatureUsage < ApplicationRecord
  # This will live in the shared database for platform analytics
  validates :organization_id, presence: true
  validates :feature_name, presence: true
  validates :usage_count, presence: true, numericality: { greater_than: 0 }

  scope :for_organization, ->(org_id) { where(organization_id: org_id) }
  scope :for_feature, ->(feature) { where(feature_name: feature) }
  scope :for_date_range, ->(start_date, end_date) { where(date: start_date..end_date) }

  def self.increment_usage(organization:, feature_name:, count: 1)
    usage = find_or_initialize_by(
      organization_id: organization.id,
      feature_name: feature_name,
      date: Date.current
    )

    if usage.persisted?
      usage.increment!(:usage_count, count)
    else
      usage.usage_count = count
      usage.save!
    end
  end
end
```

## Controller Structure

### Base Application Controller
```ruby
class ApplicationController < ActionController::API
  # Basic API controller functionality
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :record_invalid

  private

  def record_not_found(exception)
    render json: { error: "Record not found" }, status: :not_found
  end

  def record_invalid(exception)
    render json: {
      error: exception.message,
      details: exception.record.errors.full_messages
    }, status: :unprocessable_entity
  end

  def organization_id
    params[:organization_id]
  end
end
```

### Example Single-Tenant Controller Pattern
This pattern works for any resource that belongs to an organization:

```ruby
class ProjectsController < ApplicationController
  before_action :set_organization
  before_action :set_project, only: [:show, :update, :destroy]

  def index
    # All operations automatically scoped to single organization
    @projects = @organization.projects.includes(:tasks)
    render json: @projects.map { |p| project_with_stats(p) }
  end

  def show
    render json: project_with_stats(@project)
  end

  def create
    @project = @organization.projects.build(project_params)

    if @project.save
      render json: project_with_stats(@project), status: :created
    else
      render json: { errors: @project.errors }, status: :unprocessable_entity
    end
  end

  def update
    if @project.update(project_params)
      render json: project_with_stats(@project)
    else
      render json: { errors: @project.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    @project.destroy
    head :no_content
  end

  private

  def set_organization
    @organization = Organization.find(params[:organization_id])
  end

  def set_project
    @project = @organization.projects.find(params[:id])
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

## Database Schema Design

### Current Single Database Schema
```ruby
# This is what we have now - will be replicated across shards

create_table "organizations", force: :cascade do |t|
  t.string "name", null: false
  t.string "plan_type", null: false
  t.text "description"
  t.datetime "created_at", null: false
  t.datetime "updated_at", null: false
  t.index ["name"], name: "index_organizations_on_name", unique: true
end

create_table "users", force: :cascade do |t|
  t.integer "organization_id", null: false
  t.string "email", null: false
  t.string "name", null: false
  t.string "role", null: false
  t.datetime "created_at", null: false
  t.datetime "updated_at", null: false
  t.index ["organization_id"], name: "index_users_on_organization_id"
  t.index ["organization_id", "email"], name: "index_users_on_organization_id_and_email", unique: true
end

create_table "projects", force: :cascade do |t|
  t.integer "organization_id", null: false
  t.string "name", null: false
  t.text "description"
  t.string "status", default: "active", null: false
  t.datetime "created_at", null: false
  t.datetime "updated_at", null: false
  t.index ["organization_id"], name: "index_projects_on_organization_id"
  t.index ["organization_id", "name"], name: "index_projects_on_organization_id_and_name", unique: true
end

create_table "tasks", force: :cascade do |t|
  t.integer "project_id", null: false
  t.integer "organization_id", null: false
  t.integer "assigned_user_id"
  t.string "title", null: false
  t.text "description"
  t.string "status", default: "todo", null: false
  t.string "priority", default: "medium", null: false
  t.date "due_date"
  t.datetime "created_at", null: false
  t.datetime "updated_at", null: false
  t.index ["assigned_user_id"], name: "index_tasks_on_assigned_user_id"
  t.index ["organization_id"], name: "index_tasks_on_organization_id"
  t.index ["project_id"], name: "index_tasks_on_project_id"
end
```

### Future Shared Database Schema
```ruby
# These tables will live in the shared database for cross-tenant data

create_table "audit_logs", force: :cascade do |t|
  t.integer "organization_id", null: false  # Reference only, no FK constraint
  t.integer "user_id"                       # Reference only, no FK constraint
  t.string "action", null: false
  t.string "resource_type", null: false
  t.integer "resource_id", null: false
  t.json "metadata"
  t.datetime "created_at", null: false
  t.index ["organization_id"], name: "index_audit_logs_on_organization_id"
  t.index ["organization_id", "created_at"], name: "index_audit_logs_on_org_and_date"
end

create_table "feature_usage", force: :cascade do |t|
  t.integer "organization_id", null: false  # Reference only, no FK constraint
  t.string "feature_name", null: false
  t.date "date", null: false
  t.integer "usage_count", default: 0, null: false
  t.datetime "created_at", null: false
  t.datetime "updated_at", null: false
  t.index ["organization_id", "feature_name", "date"],
          name: "index_feature_usage_unique", unique: true
  t.index ["feature_name", "date"], name: "index_feature_usage_on_feature_and_date"
end
```

## Key Design Principles

### 1. Organization-Centric Design
- Every tenant-scoped model includes `organization_id`
- Organization serves as the natural shard boundary
- All business logic operates within organization context

### 2. Explicit Scoping
- Controllers always load organization first
- Related models use `@organization.projects` rather than `Project.where(...)`
- This pattern ensures queries stay within organization boundaries

### 3. Cross-Tenant Data Separation
- AuditLog and FeatureUsage models designed for shared database
- Use integer references without foreign key constraints
- Enable platform-wide analytics and compliance

### 4. Future-Proofed Structure
- Models include `shard_key` method for routing
- Controllers follow patterns that work with middleware routing
- Database schema designed to be replicated across shards

This structure allows the application to work perfectly as a single-database application today, while being ready for sharding implementation when needed.