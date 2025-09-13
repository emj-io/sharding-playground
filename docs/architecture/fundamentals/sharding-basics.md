# Sharding Basics

## What is Sharding?

Sharding is a database scaling technique where you split data across multiple databases (called "shards") to distribute load and enable horizontal scaling. Each shard is a separate database that contains a subset of your total data.

## Single-Tenant-Per-Shard Model

In our approach, each tenant (organization) gets their own dedicated database. This is the simplest and most isolated form of sharding:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Shard 1       │    │   Shard 2       │    │   Shard 3       │
│ Organization A  │    │ Organization B  │    │ Organization C  │
│                 │    │                 │    │                 │
│ ├─ users        │    │ ├─ users        │    │ ├─ users        │
│ ├─ projects     │    │ ├─ projects     │    │ ├─ projects     │
│ └─ tasks        │    │ └─ tasks        │    │ └─ tasks        │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Why Single-Tenant-Per-Shard?

### ✅ Advantages

1. **Perfect Isolation**: Each tenant's data is completely separate
2. **Simple Development**: Developers rarely need to think about sharding
3. **Easy Backup/Restore**: Can backup/restore individual tenants
4. **Performance Predictability**: One tenant can't affect another's performance
5. **Compliance Friendly**: Great for data sovereignty requirements
6. **Schema Evolution**: Can have different schema versions per tenant
7. **Easier Debugging**: Issues are isolated to specific tenants

### ❌ Disadvantages

1. **Resource Overhead**: Each database has overhead (connections, memory)
2. **Cross-Tenant Operations**: Queries across tenants are more complex
3. **Database Limits**: Limited by maximum databases your system can handle
4. **Management Complexity**: More databases to monitor and maintain

## When to Use This Approach

### ✅ Good Fit When:
- You have medium to large tenants (not thousands of tiny ones)
- Strong data isolation requirements
- Tenants have different usage patterns
- Compliance requires data separation
- Cross-tenant queries are rare
- Each tenant justifies the database overhead

### ❌ Poor Fit When:
- You have thousands of very small tenants
- Frequent cross-tenant analytics required
- Very limited database connection pools
- Shared data structures across tenants

## Developer Experience Goals

Our implementation prioritizes developer simplicity:

1. **Transparent Routing**: Framework automatically routes to correct shard
2. **Standard Rails Patterns**: Regular ActiveRecord works for single-tenant operations
3. **Clear Boundaries**: Obvious when you're doing cross-tenant operations
4. **Minimal Configuration**: Shard routing happens automatically

## Example: How It Works

```ruby
# This just works - framework routes to Organization 123's shard
organization = Organization.find(123)
users = organization.users.where(active: true)

# Cross-tenant operations are explicit and obvious
all_organizations = Admin::CrossTenantQuery.organizations.with_stats
```

## Performance Characteristics

### Single-Tenant Operations (99% of cases)
- **Fast**: Query only one database
- **Predictable**: No cross-shard complexity
- **Scalable**: Each shard handles fewer organizations

### Cross-Tenant Operations (1% of cases)
- **Slower**: Must query multiple databases
- **Complex**: Require aggregation logic
- **Limited**: Some queries become impossible

## Next Steps

- [Multi-Tenancy Patterns](./multi-tenancy-patterns.md) - Understand different multi-tenancy approaches
- [Data Modeling for Sharding](./data-modeling.md) - How to design your schema
- [Shard Key Selection](../patterns/shard-key-selection.md) - Choosing your sharding strategy