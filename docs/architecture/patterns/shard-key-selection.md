# Shard Key Selection

## Our Choice: Organization ID

### Requirements Met
- **Perfect isolation**: Each tenant gets own database
- **Simple routing**: `organization_id` → shard mapping
- **No hotspots**: Assumes organizations are similarly sized
- **Developer friendly**: Transparent for single-tenant operations

### Implementation
```ruby
# Simple modulo-based routing
def shard_for_organization(organization_id)
  shard_number = organization_id % SHARD_COUNT
  "tenant_#{shard_number}_db"
end
```

## Alternatives Considered

### 1. User ID as Shard Key
❌ **Rejected**: Users belong to organizations. Would split organization data across shards.

### 2. Geographic Sharding
❌ **Rejected**: Adds complexity without clear benefit for our use case.

### 3. Hash-Based Sharding
✅ **Possible**: Could use `organization.name.hash % SHARD_COUNT` for more even distribution.

## Tradeoffs

### ✅ Benefits
- **Simple implementation**: Direct mapping from org ID to shard
- **Perfect tenant isolation**: No cross-tenant data leakage
- **Predictable performance**: Each organization's performance is isolated
- **Easy debugging**: All tenant data in one place

### ❌ Limitations
- **Uneven distribution**: Organization IDs might not distribute evenly
- **Large tenant problem**: One very large organization can overwhelm a shard
- **Rebalancing difficulty**: Hard to move tenants between shards later

## Distribution Strategy

### Current: Modulo Distribution
```ruby
# Organizations 1, 4, 7 → Shard 0
# Organizations 2, 5, 8 → Shard 1
# Organizations 3, 6, 9 → Shard 2
shard = organization_id % 3
```

**Problems**:
- If organization IDs are sequential, distribution is even
- If organization IDs have patterns, distribution may be uneven

### Alternative: Hash Distribution
```ruby
# More even distribution regardless of ID patterns
shard = Digest::SHA1.hexdigest(organization_id.to_s)[0..7].to_i(16) % SHARD_COUNT
```

**Tradeoff**: More complex but better distribution.

## Hotspot Management

### Problem: Large Organizations
If Organization 123 has 10,000 users and Organization 124 has 10 users, but they're on the same shard:

```
Shard 0: Org 123 (10,000 users) + Org 126 (50 users) = 10,050 users
Shard 1: Org 124 (10 users) + Org 127 (15 users) = 25 users
```

### Solutions

#### 1. Dedicated Shards for Large Tenants
```ruby
def shard_for_organization(organization_id)
  # Large tenants get dedicated shards
  case organization_id
  when 123 then "tenant_123_dedicated_db"
  when 456 then "tenant_456_dedicated_db"
  else
    # Small tenants share shards
    "tenant_#{organization_id % SMALL_TENANT_SHARD_COUNT}_db"
  end
end
```

#### 2. Tenant Size-Based Routing
```ruby
def shard_for_organization(organization_id)
  org_size = OrganizationSize.cached_size(organization_id)

  case org_size
  when :large then "large_tenant_#{organization_id % LARGE_SHARD_COUNT}_db"
  when :medium then "medium_tenant_#{organization_id % MEDIUM_SHARD_COUNT}_db"
  else "small_tenant_#{organization_id % SMALL_SHARD_COUNT}_db"
  end
end
```

## Routing Requirements

### For Developers (Must Be Transparent)
```ruby
# This should work without thinking about sharding
organization = Organization.find(123)
users = organization.users.active
```

### For Framework (Must Handle Routing)
```ruby
# Framework must intercept Organization.find() and route to correct shard
class Organization < ApplicationRecord
  def self.find(id)
    connection_handler.with_shard_for_organization(id) do
      super
    end
  end
end
```

### For Cross-Tenant Operations (Must Be Explicit)
```ruby
# Cross-tenant operations should be obvious
all_orgs = Admin::CrossTenantQuery.all_organizations
platform_stats = Admin::Analytics.platform_wide_metrics
```

## Implementation Constraints

### Database Connection Limits
- **SQLite**: No limit on number of databases
- **PostgreSQL**: Limited by `max_connections` setting
- **MySQL**: Limited by `max_connections` setting

### Memory Usage
Each database connection pool uses memory. With 100 shards × 5 connections = 500 database connections.

### Migration Complexity
Every schema change must be applied to every shard database.

## Next Steps
- [Cross-Shard Queries](./cross-shard-queries.md) - Handling operations across multiple shards
- [Rails Sharding Setup](../implementation/rails-sharding-setup.md) - Implementing this routing strategy