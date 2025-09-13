# Consistency Models

## Single-Tenant-Per-Shard Consistency

### Within a Shard (Strong Consistency)
- **All operations within one tenant**: ACID guarantees apply
- **Transactions work normally**: Can use Rails transactions, database constraints
- **Real-time consistency**: Changes are immediately visible

```ruby
# This works with full ACID guarantees
organization.transaction do
  user = organization.users.create!(name: "John")
  project = organization.projects.create!(name: "Project A")
  project.tasks.create!(title: "Task 1", assigned_user: user)
end
```

### Across Shards (Eventually Consistent)
- **Cross-tenant operations**: No ACID guarantees
- **No distributed transactions**: Cannot span multiple databases
- **Eventual consistency only**: Updates may be visible at different times

```ruby
# This CANNOT be done in a transaction
Admin::CrossTenantOperation.execute do |op|
  op.update_all_organizations(new_setting: "value")  # Each org updated separately
  op.aggregate_platform_metrics  # May see inconsistent state during updates
end
```

## Requirements

### Developer Must Handle
1. **Cross-shard data inconsistency**: Accept that cross-tenant data may be temporarily inconsistent
2. **No cross-shard transactions**: Design workflows that don't require them
3. **Idempotent operations**: Make cross-tenant operations repeatable

### Framework Provides
1. **Single-shard ACID**: Full consistency within each tenant
2. **Automatic shard routing**: Transparent for single-tenant operations
3. **Cross-shard aggregation**: Utilities for collecting data across tenants

## Limitations

### What You Cannot Do
- Enforce foreign keys across shards
- Use database joins across tenants
- Guarantee immediate consistency across tenants
- Use distributed transactions

### What You Must Design For
- Eventual consistency in cross-tenant reports
- Compensating actions for failed cross-tenant operations
- Graceful handling of temporarily inconsistent states

## Implementation Impact

### Single-Tenant Operations (No Impact)
```ruby
# Normal Rails code - full ACID guarantees
class ProjectsController < ApplicationController
  def create
    @organization.transaction do
      @project = @organization.projects.create!(project_params)
      AuditLog.log_action(organization: @organization, action: "created_project", resource: @project)
    end
  end
end
```

### Cross-Tenant Operations (Requires Design)
```ruby
# Must handle inconsistency
class Admin::MetricsController < ApplicationController
  def platform_stats
    # This may show inconsistent data during updates
    @stats = ShardedQuery.aggregate_all_tenants do |tenant_stats|
      {
        organization_count: tenant_stats[:organizations],
        user_count: tenant_stats[:users],
        project_count: tenant_stats[:projects]
      }
    end
  end
end
```