# Cross-Shard Queries

## The Problem

With single-tenant-per-shard, each organization's data is isolated. Cross-tenant operations require querying multiple databases and aggregating results.

## Query Types

### 1. Simple Aggregation (Most Common)
**Need**: Platform-wide statistics

```ruby
# Bad: Inefficient, queries each shard separately
total_users = 0
Organization.all_shards.each do |shard|
  shard.connect do
    total_users += User.count
  end
end

# Good: Parallel queries with result aggregation
results = Organization.query_all_shards_parallel do |shard_connection|
  { user_count: shard_connection.exec("SELECT COUNT(*) FROM users")[0]['count'] }
end
total_users = results.sum { |r| r[:user_count] }
```

### 2. Collection with Details
**Need**: List all organizations with stats

```ruby
# Implementation: Collect from each shard
organizations_with_stats = Organization.collect_from_all_shards do |shard_connection|
  shard_connection.exec(<<~SQL)
    SELECT
      o.id, o.name, o.plan_type,
      (SELECT COUNT(*) FROM users WHERE organization_id = o.id) as user_count,
      (SELECT COUNT(*) FROM projects WHERE organization_id = o.id) as project_count
    FROM organizations o
  SQL
end.flatten
```

### 3. Search Across Tenants
**Need**: Find all users with email pattern

```ruby
# Limited: Can search but results may be incomplete due to timeouts
matching_users = Organization.search_all_shards(timeout: 5.seconds) do |shard_connection|
  shard_connection.exec("SELECT * FROM users WHERE email LIKE ?", "%@example.com%")
end.flatten
```

## Implementation Patterns

### Pattern 1: Sequential Query
```ruby
class CrossTenantQuery
  def self.all_organizations
    results = []

    Organization.all_shard_names.each do |shard_name|
      begin
        ActiveRecord::Base.connected_to(shard: shard_name) do
          results.concat(Organization.all.to_a)
        end
      rescue ActiveRecord::ConnectionNotEstablished
        # Shard may be offline, continue with others
        Rails.logger.warn "Shard #{shard_name} unavailable"
      end
    end

    results
  end
end
```

**Tradeoffs**:
- ✅ Simple implementation
- ❌ Slow (serial execution)
- ❌ Fails if any shard is down

### Pattern 2: Parallel Query with Timeout
```ruby
class CrossTenantQuery
  def self.all_organizations_parallel
    futures = Organization.all_shard_names.map do |shard_name|
      Concurrent::Future.execute do
        ActiveRecord::Base.connected_to(shard: shard_name) do
          Organization.all.to_a
        end
      rescue StandardError => e
        Rails.logger.error "Failed to query shard #{shard_name}: #{e.message}"
        []
      end
    end

    # Wait for all queries with timeout
    results = futures.map { |f| f.value(5.seconds) rescue [] }
    results.flatten
  end
end
```

**Tradeoffs**:
- ✅ Fast (parallel execution)
- ✅ Resilient (handles shard failures)
- ❌ Complex (requires threading)
- ❌ Resource intensive (multiple connections)

### Pattern 3: Cached Aggregation
```ruby
class PlatformMetrics
  def self.cached_stats
    Rails.cache.fetch("platform_stats", expires_in: 15.minutes) do
      calculate_fresh_stats
    end
  end

  private

  def self.calculate_fresh_stats
    stats = Organization.query_all_shards_parallel do |shard_connection|
      {
        organization_count: shard_connection.exec("SELECT COUNT(*) FROM organizations")[0]['count'],
        user_count: shard_connection.exec("SELECT COUNT(*) FROM users")[0]['count'],
        project_count: shard_connection.exec("SELECT COUNT(*) FROM projects")[0]['count']
      }
    end

    {
      total_organizations: stats.sum { |s| s[:organization_count] },
      total_users: stats.sum { |s| s[:user_count] },
      total_projects: stats.sum { |s| s[:project_count] },
      calculated_at: Time.current
    }
  end
end
```

**Tradeoffs**:
- ✅ Very fast for reads (cached)
- ✅ Reduces database load
- ❌ Data may be stale
- ❌ Cache invalidation complexity

## Limitations

### What You Cannot Do
- **Join across shards**: No SQL joins spanning multiple databases
- **Transactions across shards**: No ACID guarantees across tenants
- **Real-time consistency**: Cross-tenant data may be temporarily inconsistent
- **Complex aggregations**: Cannot use SQL aggregation functions across shards

### Performance Constraints
- **Query time increases** with number of shards
- **Memory usage** for collecting large result sets
- **Connection pool** exhaustion with parallel queries
- **Timeout handling** for slow or unavailable shards

## Best Practices

### 1. Design to Avoid Cross-Shard Queries
```ruby
# Bad: Frequent cross-tenant queries in user-facing features
def dashboard_stats
  CrossTenantQuery.platform_metrics  # Slow!
end

# Good: Use cross-tenant queries only in admin interfaces
def admin_dashboard_stats
  PlatformMetrics.cached_stats  # Fast, acceptable staleness
end
```

### 2. Cache Aggressively
```ruby
# Cache expensive cross-shard aggregations
class OrganizationStats
  def self.platform_summary
    Rails.cache.fetch("org_stats_summary", expires_in: 1.hour) do
      expensive_cross_shard_calculation
    end
  end
end
```

### 3. Use Background Jobs for Heavy Aggregations
```ruby
# Don't block user requests with cross-shard queries
class PlatformMetricsJob < ApplicationJob
  def perform
    stats = CrossTenantQuery.calculate_platform_metrics
    Rails.cache.write("platform_metrics", stats, expires_in: 1.hour)
  end
end
```

### 4. Handle Failures Gracefully
```ruby
class CrossTenantQuery
  def self.best_effort_query
    results = []
    failed_shards = []

    Organization.all_shard_names.each do |shard_name|
      begin
        Timeout.timeout(5.seconds) do
          ActiveRecord::Base.connected_to(shard: shard_name) do
            results.concat(yield)
          end
        end
      rescue StandardError => e
        failed_shards << shard_name
        Rails.logger.warn "Shard #{shard_name} failed: #{e.message}"
      end
    end

    {
      results: results,
      failed_shards: failed_shards,
      success_rate: ((Organization.all_shard_names.count - failed_shards.count) / Organization.all_shard_names.count.to_f * 100).round(2)
    }
  end
end
```

## Alternative: Pre-Aggregated Data

Instead of real-time cross-shard queries, maintain aggregated data:

```ruby
# Store aggregated data in shared database
class PlatformStatistic < ApplicationRecord
  # This lives in the shared database, not tenant shards

  def self.update_from_all_shards
    transaction do
      delete_all  # Clear old stats

      Organization.query_all_shards do |shard_name, stats|
        create!(
          shard_name: shard_name,
          organization_count: stats[:orgs],
          user_count: stats[:users],
          project_count: stats[:projects],
          calculated_at: Time.current
        )
      end
    end
  end

  def self.platform_totals
    {
      organizations: sum(:organization_count),
      users: sum(:user_count),
      projects: sum(:project_count),
      last_updated: maximum(:calculated_at)
    }
  end
end

# Update via background job
class UpdatePlatformStatsJob < ApplicationJob
  def perform
    PlatformStatistic.update_from_all_shards
  end
end
```

## Next Steps
- [Data Migration](./data-migration.md) - Moving data between shards
- [Connection Management](../implementation/connection-management.md) - Managing database connections