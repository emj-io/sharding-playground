# Multi-Tenancy Patterns

There are three main patterns for implementing multi-tenancy. Understanding these helps explain why we chose the single-tenant-per-shard approach.

## 1. Shared Database, Shared Schema (Row-Level Security)

All tenants share the same database and tables, with a `tenant_id` column to separate data.

```sql
-- All tenants in same table
users (id, tenant_id, name, email)
projects (id, tenant_id, name, description)
```

### ✅ Advantages
- Simple to implement initially
- Efficient resource utilization
- Easy cross-tenant queries

### ❌ Disadvantages
- No data isolation
- Risk of data leaks
- Performance impact from one tenant affects all
- Difficult to backup individual tenants

## 2. Shared Database, Separate Schemas

All tenants share a database but each gets their own schema.

```sql
-- Separate schemas per tenant
tenant_123.users (id, name, email)
tenant_123.projects (id, name, description)

tenant_456.users (id, name, email)
tenant_456.projects (id, name, description)
```

### ✅ Advantages
- Better isolation than shared schema
- Efficient connection pooling
- Schema-level security

### ❌ Disadvantages
- Database-specific feature (PostgreSQL schemas, MySQL databases)
- Complex connection management
- Cross-tenant queries still possible but complex

## 3. Separate Databases (Our Choice)

Each tenant gets their own complete database.

```sql
-- Completely separate databases
tenant_123_db.users (id, name, email)
tenant_123_db.projects (id, name, description)

tenant_456_db.users (id, name, email)
tenant_456_db.projects (id, name, description)
```

### ✅ Advantages
- Perfect data isolation
- Independent scaling and performance
- Easy backup/restore per tenant
- Different schema versions possible
- Clear compliance boundaries

### ❌ Disadvantages
- Higher resource overhead
- Complex cross-tenant operations
- More databases to manage

## Why We Chose Separate Databases

For our sharding playground, separate databases provide:

### 1. **Developer Simplicity**
```ruby
# Developer writes normal Rails code
organization = Organization.find(123)
users = organization.users.includes(:projects)

# Framework handles routing to tenant_123_db automatically
```

### 2. **Clear Mental Model**
- Single-tenant operations: "Just write normal Rails code"
- Cross-tenant operations: "Use explicit admin controllers"

### 3. **Perfect Isolation**
- No risk of tenant data leakage
- One tenant's queries don't affect others
- Independent database tuning per tenant

### 4. **Operational Benefits**
```ruby
# Easy tenant-specific operations
backup_tenant_database(organization_id: 123)
restore_tenant_database(organization_id: 123, backup_file: "backup.sql")
migrate_tenant_schema(organization_id: 123, version: "2.1.0")
```

## Implementation Pattern: Transparent Routing

Our implementation makes sharding transparent for single-tenant operations:

```ruby
# In your Rails controller - no sharding logic needed
class ProjectsController < ApplicationController
  before_action :set_organization

  def index
    # This automatically queries the correct shard
    @projects = @organization.projects
  end

  def create
    # This automatically creates in the correct shard
    @project = @organization.projects.create!(project_params)
  end

  private

  def set_organization
    @organization = Organization.find(params[:organization_id])
    # Middleware automatically connects to correct shard
  end
end
```

## Cross-Tenant Operations

When you DO need cross-tenant data, we make it explicit:

```ruby
# Explicit cross-tenant controller
class Admin::OrganizationsController < Admin::BaseController
  def index
    # This queries ALL shards and aggregates results
    @organizations = CrossTenantQuery.all_organizations_with_stats
  end

  def analytics
    # This aggregates data across all tenants
    @metrics = CrossTenantAnalytics.platform_metrics(
      start_date: params[:start_date],
      end_date: params[:end_date]
    )
  end
end
```

## Migration Considerations

### From Shared to Separate Databases

If you're migrating from a shared database:

1. **Extract tenant data**: Query by `tenant_id` to get each tenant's data
2. **Create shard databases**: One database per tenant
3. **Migrate data**: Move each tenant's data to their dedicated database
4. **Update application**: Add sharding middleware and routing
5. **Verify isolation**: Ensure no cross-tenant data access

### Schema Evolution

With separate databases, you can:
- Migrate tenants independently
- Test schema changes on specific tenants
- Roll back problematic migrations per tenant
- Support different schema versions temporarily

## Next Steps

- [Data Modeling for Sharding](./data-modeling.md) - How to design your schema for this pattern
- [Shard Key Selection](../patterns/shard-key-selection.md) - Choosing your routing strategy
- [Rails Sharding Setup](../implementation/rails-sharding-setup.md) - Implementing this in Rails