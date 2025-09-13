# Data Modeling for Sharding

When implementing single-tenant-per-shard architecture, your data model design becomes crucial for maintaining developer simplicity while enabling effective sharding.

## Core Principles

### 1. **Clear Tenant Boundaries**
Every piece of data should have a clear tenant owner. In our case, everything belongs to an `Organization`.

```ruby
# Good: Clear tenant ownership
class User < ApplicationRecord
  belongs_to :organization  # Tenant boundary
  # All user data isolated per organization
end

class Project < ApplicationRecord
  belongs_to :organization  # Tenant boundary
  has_many :tasks
end

# Good: Inherits tenant from parent
class Task < ApplicationRecord
  belongs_to :project
  belongs_to :organization  # Denormalized for performance
end
```

### 2. **Denormalize Tenant ID**
Store the tenant ID (organization_id) on every record, even when it can be derived from associations.

```ruby
# Before: Tenant ID only on top-level models
class Task < ApplicationRecord
  belongs_to :project
  # organization_id derived via project.organization_id
end

# After: Denormalized for sharding
class Task < ApplicationRecord
  belongs_to :project
  belongs_to :organization  # Explicit tenant ownership

  validates :organization_id, presence: true
  validate :project_belongs_to_organization

  private

  def project_belongs_to_organization
    return unless project && organization

    unless project.organization_id == organization_id
      errors.add(:project, "must belong to the same organization")
    end
  end
end
```

### 3. **Avoid Cross-Tenant References**
Never create foreign keys that span tenants. This prevents accidental cross-tenant data access.

```ruby
# Bad: Cross-tenant reference
class SharedTemplate < ApplicationRecord
  has_many :projects  # Projects from different organizations!
end

# Good: Tenant-specific templates
class ProjectTemplate < ApplicationRecord
  belongs_to :organization
  has_many :projects, foreign_key: :template_id
end
```

## Data Categories

### Tenant-Scoped Data (99% of your data)
This data lives in individual shard databases:

```ruby
# Primary business entities
class Organization < ApplicationRecord
  has_many :users
  has_many :projects
  has_many :tasks
end

class User < ApplicationRecord
  belongs_to :organization
  has_many :assigned_tasks, class_name: 'Task'
end

class Project < ApplicationRecord
  belongs_to :organization
  has_many :tasks
end

class Task < ApplicationRecord
  belongs_to :organization
  belongs_to :project
  belongs_to :assigned_user, class_name: 'User', optional: true
end
```

### Cross-Tenant Data (1% of your data)
This data lives in a shared database for platform-wide operations:

```ruby
# Audit logs for compliance
class AuditLog < ApplicationRecord
  # Stored in shared database
  # Contains organization_id for filtering but doesn't belong_to organization

  validates :organization_id, presence: true
  validates :action, presence: true
  validates :resource_type, presence: true
end

# Platform-wide analytics
class FeatureUsage < ApplicationRecord
  # Stored in shared database
  # Aggregated data across all tenants

  validates :organization_id, presence: true
  validates :feature_name, presence: true
  validates :usage_count, presence: true
end

# System-wide configuration
class SystemConfiguration < ApplicationRecord
  # Global settings that apply to all tenants
  # No organization_id needed
end
```

## Schema Design Patterns

### 1. **Standard Tenant Pattern**
Most models follow this pattern:

```ruby
class StandardModel < ApplicationRecord
  belongs_to :organization

  # Always scope queries by organization
  scope :for_organization, ->(org) { where(organization: org) }

  # Validate tenant ownership
  validates :organization, presence: true

  # Auto-set organization from context when possible
  before_validation :set_organization_from_context, if: :organization_context_available?

  private

  def organization_context_available?
    Current.organization.present? && organization.blank?
  end

  def set_organization_from_context
    self.organization = Current.organization
  end
end
```

### 2. **Hierarchical Tenant Pattern**
For models that inherit tenant from parents:

```ruby
class Task < ApplicationRecord
  belongs_to :project
  belongs_to :organization

  # Validate data consistency
  validate :project_belongs_to_organization

  # Auto-inherit organization from project
  before_validation :inherit_organization_from_project

  private

  def project_belongs_to_organization
    return unless project && organization

    unless project.organization_id == organization_id
      errors.add(:project, "must belong to the same organization")
    end
  end

  def inherit_organization_from_project
    self.organization ||= project&.organization
  end
end
```

### 3. **Cross-Tenant Reference Pattern**
When you need to reference tenant data from shared data:

```ruby
class AuditLog < ApplicationRecord
  # Don't use belongs_to :organization (cross-database reference)
  # Instead, store organization_id and provide helper methods

  validates :organization_id, presence: true

  def organization
    # Explicitly query the correct shard
    Organization.on_shard_for_organization(organization_id)
                .find(organization_id)
  end

  def organization_name
    # Cache frequently accessed data to avoid cross-database queries
    Rails.cache.fetch("org_name_#{organization_id}", expires_in: 1.hour) do
      organization&.name
    end
  end
end
```

## Database Schema Example

### Tenant Database Schema
Each tenant gets this complete schema:

```sql
-- tenant_123_db schema
CREATE TABLE organizations (
  id BIGINT PRIMARY KEY,
  name VARCHAR NOT NULL,
  plan_type VARCHAR NOT NULL,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE users (
  id BIGINT PRIMARY KEY,
  organization_id BIGINT NOT NULL REFERENCES organizations(id),
  email VARCHAR NOT NULL,
  name VARCHAR NOT NULL,
  role VARCHAR NOT NULL,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE projects (
  id BIGINT PRIMARY KEY,
  organization_id BIGINT NOT NULL REFERENCES organizations(id),
  name VARCHAR NOT NULL,
  description TEXT,
  status VARCHAR NOT NULL,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE TABLE tasks (
  id BIGINT PRIMARY KEY,
  organization_id BIGINT NOT NULL REFERENCES organizations(id),
  project_id BIGINT NOT NULL REFERENCES projects(id),
  assigned_user_id BIGINT REFERENCES users(id),
  title VARCHAR NOT NULL,
  description TEXT,
  status VARCHAR NOT NULL,
  priority VARCHAR NOT NULL,
  due_date DATE,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);
```

### Shared Database Schema
One shared database for cross-tenant data:

```sql
-- shared_db schema
CREATE TABLE audit_logs (
  id BIGINT PRIMARY KEY,
  organization_id BIGINT NOT NULL,  -- Reference only, no FK
  user_id BIGINT,                   -- Reference only, no FK
  action VARCHAR NOT NULL,
  resource_type VARCHAR NOT NULL,
  resource_id BIGINT NOT NULL,
  metadata JSONB,
  created_at TIMESTAMP
);

CREATE TABLE feature_usage (
  id BIGINT PRIMARY KEY,
  organization_id BIGINT NOT NULL,  -- Reference only, no FK
  feature_name VARCHAR NOT NULL,
  usage_count INTEGER NOT NULL,
  date DATE NOT NULL,
  created_at TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE INDEX idx_audit_logs_org_date ON audit_logs(organization_id, created_at);
CREATE INDEX idx_feature_usage_org_feature_date ON feature_usage(organization_id, feature_name, date);
```

## Migration Strategy

### Adding New Models

When adding a new tenant-scoped model:

```ruby
# Migration for tenant databases
class CreateInvoices < ActiveRecord::Migration[8.0]
  def change
    create_table :invoices do |t|
      t.references :organization, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.decimal :amount, precision: 10, scale: 2, null: false
      t.string :status, null: false, default: 'draft'
      t.date :due_date
      t.timestamps
    end

    add_index :invoices, [:organization_id, :status]
    add_index :invoices, [:organization_id, :due_date]
  end
end

# Model follows standard tenant pattern
class Invoice < ApplicationRecord
  belongs_to :organization
  belongs_to :project

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :status, inclusion: { in: %w[draft sent paid overdue] }

  validate :project_belongs_to_organization

  before_validation :inherit_organization_from_project

  private

  def project_belongs_to_organization
    return unless project && organization
    unless project.organization_id == organization_id
      errors.add(:project, "must belong to the same organization")
    end
  end

  def inherit_organization_from_project
    self.organization ||= project&.organization
  end
end
```

## Data Integrity Considerations

### 1. **Foreign Key Constraints**
Use them within tenant databases, but never across databases:

```ruby
# Good: Within same tenant database
add_foreign_key :tasks, :projects
add_foreign_key :tasks, :organizations

# Bad: Across databases (impossible anyway)
# add_foreign_key :audit_logs, :organizations  # This would fail
```

### 2. **Validation Strategy**
Validate data integrity at the application level:

```ruby
class Task < ApplicationRecord
  belongs_to :organization
  belongs_to :project
  belongs_to :assigned_user, optional: true

  validate :assigned_user_belongs_to_organization
  validate :project_belongs_to_organization

  private

  def assigned_user_belongs_to_organization
    return unless assigned_user && organization
    unless assigned_user.organization_id == organization_id
      errors.add(:assigned_user, "must belong to the same organization")
    end
  end

  def project_belongs_to_organization
    return unless project && organization
    unless project.organization_id == organization_id
      errors.add(:project, "must belong to the same organization")
    end
  end
end
```

## Next Steps

- [Consistency Models](./consistency-models.md) - Understanding consistency in sharded systems
- [Shard Key Selection](../patterns/shard-key-selection.md) - Choosing your sharding strategy
- [Rails Sharding Setup](../implementation/rails-sharding-setup.md) - Implementing this data model in Rails