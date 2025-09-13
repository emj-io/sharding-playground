# Monitoring & Observability

## Single-Shard-Per-Request Monitoring

### Request-Level Metrics
Each request should be tagged with its shard to track per-tenant performance:

```ruby
class ShardingMiddleware
  def call(env)
    organization_id = extract_organization_id(env)
    shard_name = ShardRouter.shard_for_organization(organization_id)

    # Tag all metrics with shard info
    ActiveSupport::Notifications.instrument('request.shard',
      shard: shard_name,
      organization_id: organization_id
    ) do
      @app.call(env)
    end
  end
end
```

### Key Metrics to Track

#### Per-Shard Performance
```ruby
# Response times by shard
shard_response_times = {
  "shard_0" => [120ms, 95ms, 200ms],
  "shard_1" => [50ms, 45ms, 80ms],
  "shard_2" => [2000ms, 1800ms, 2200ms]  # Problem!
}

# Database connection usage by shard
shard_connection_usage = {
  "shard_0" => "3/5 connections",
  "shard_1" => "2/5 connections",
  "shard_2" => "5/5 connections"  # Saturated!
}
```

#### Cross-Request Patterns
```ruby
# Requests that hit multiple shards (should be rare)
class MultiShardRequestDetector
  def self.track_request(request_id, shards_accessed)
    if shards_accessed.count > 1
      Rails.logger.warn "Request #{request_id} accessed multiple shards: #{shards_accessed}"
      # This indicates a design problem
    end
  end
end
```

## Health Checks

### Per-Shard Health
```ruby
class ShardHealthChecker
  def self.check_all_shards
    results = {}

    Organization.all_shard_names.each do |shard_name|
      results[shard_name] = check_shard(shard_name)
    end

    results
  end

  private

  def self.check_shard(shard_name)
    start_time = Time.current

    ActiveRecord::Base.connected_to(shard: shard_name) do
      # Simple query to verify shard is responsive
      Organization.connection.execute("SELECT 1")

      {
        status: :healthy,
        response_time: (Time.current - start_time) * 1000,
        connection_pool: connection_pool_status
      }
    end
  rescue StandardError => e
    {
      status: :unhealthy,
      error: e.message,
      response_time: nil
    }
  end

  def self.connection_pool_status
    pool = Organization.connection_pool
    {
      size: pool.size,
      checked_out: pool.checked_out.count,
      available: pool.available.count
    }
  end
end
```

### Health Check Endpoint
```ruby
# config/routes.rb
get '/health/shards', to: 'health#shards'

class HealthController < ApplicationController
  def shards
    results = ShardHealthChecker.check_all_shards

    overall_status = results.values.all? { |r| r[:status] == :healthy } ? :healthy : :degraded

    render json: {
      overall_status: overall_status,
      shard_details: results,
      checked_at: Time.current
    }
  end
end
```

## Alerting Rules

### Critical Alerts
```ruby
# Shard completely down
if shard_status == :unhealthy
  alert(
    severity: :critical,
    message: "Shard #{shard_name} is unhealthy: #{error}",
    impact: "All organizations on this shard affected"
  )
end

# Shard response time degraded
if shard_response_time > 5000  # 5 seconds
  alert(
    severity: :warning,
    message: "Shard #{shard_name} response time: #{shard_response_time}ms",
    impact: "Performance degraded for organizations: #{affected_orgs}"
  )
end

# Connection pool exhausted
if connection_pool_usage > 90
  alert(
    severity: :warning,
    message: "Shard #{shard_name} connection pool at #{connection_pool_usage}%",
    impact: "May cause connection timeouts"
  )
end
```

## Logging Strategy

### Request Context
```ruby
class ShardContextLogger
  def self.add_shard_context(organization_id)
    shard_name = ShardRouter.shard_for_organization(organization_id)

    Rails.logger.tagged("shard:#{shard_name}", "org:#{organization_id}") do
      yield
    end
  end
end

# Usage in controllers
class ProjectsController < ApplicationController
  around_action :log_with_shard_context

  private

  def log_with_shard_context
    ShardContextLogger.add_shard_context(@organization.id) do
      yield
    end
  end
end
```

### Structured Logging
```ruby
# Include shard info in all log entries
Rails.logger.info({
  event: "project_created",
  organization_id: @organization.id,
  shard: ShardRouter.shard_for_organization(@organization.id),
  project_id: @project.id,
  user_id: current_user.id,
  duration_ms: 120
})
```

## Performance Monitoring

### Database Query Tracking
```ruby
class ShardQueryTracker
  def self.track_query(shard_name, sql, duration)
    # Track slow queries per shard
    if duration > 1000  # 1 second
      Rails.logger.warn({
        event: "slow_query",
        shard: shard_name,
        sql: sql,
        duration_ms: duration
      })
    end

    # Update metrics
    ShardMetrics.record_query(shard_name, duration)
  end
end
```

### Load Distribution Monitoring
```ruby
class ShardLoadMonitor
  def self.check_distribution
    load_by_shard = Organization.all_shard_names.map do |shard_name|
      [shard_name, calculate_shard_load(shard_name)]
    end.to_h

    # Alert if load is very uneven
    max_load = load_by_shard.values.max
    min_load = load_by_shard.values.min

    if max_load > min_load * 3  # 3x difference
      alert_uneven_distribution(load_by_shard)
    end

    load_by_shard
  end

  private

  def self.calculate_shard_load(shard_name)
    ActiveRecord::Base.connected_to(shard: shard_name) do
      {
        organization_count: Organization.count,
        user_count: User.count,
        active_requests: current_request_count_for_shard(shard_name)
      }
    end
  end
end
```

## Error Tracking

### Shard-Specific Errors
```ruby
class ShardErrorTracker
  def self.track_error(error, context = {})
    error_data = {
      error_class: error.class.name,
      error_message: error.message,
      shard: context[:shard],
      organization_id: context[:organization_id],
      request_id: context[:request_id],
      occurred_at: Time.current
    }

    # Send to error tracking service
    ErrorTrackingService.report(error_data)

    # Track error rates per shard
    ShardMetrics.increment_error_count(context[:shard])
  end
end
```

## Limitations

### Cannot Monitor
- **Cross-shard transactions**: Don't exist in our model
- **Distributed query performance**: Each request hits one shard
- **Global consistency**: Each shard is independent

### Must Monitor
- **Per-shard performance**: Each shard can have different characteristics
- **Load distribution**: Some shards may be much busier
- **Connection pool usage**: Limited connections per shard
- **Schema consistency**: Migrations may leave shards in different states

## Dashboard Requirements

### Shard Overview Dashboard
```
┌─────────────────────────────────────────────────────────────┐
│ Shard Health Overview                                       │
├─────────────────────────────────────────────────────────────┤
│ ✓ shard_0: 45ms avg, 12 orgs, 3/5 connections            │
│ ⚠ shard_1: 230ms avg, 8 orgs, 5/5 connections            │
│ ✗ shard_2: Error - connection timeout                      │
│ ✓ shard_3: 67ms avg, 15 orgs, 2/5 connections            │
└─────────────────────────────────────────────────────────────┘
```

### Per-Shard Detail Dashboard
```
┌─────────────────────────────────────────────────────────────┐
│ Shard 1 Details                                            │
├─────────────────────────────────────────────────────────────┤
│ Organizations: 8                                            │
│ Total Users: 1,245                                          │
│ Avg Response Time: 230ms                                    │
│ 95th Percentile: 890ms                                      │
│ Connection Pool: 5/5 (100% utilized)                      │
│ Recent Errors: 3 in last hour                              │
└─────────────────────────────────────────────────────────────┘
```

## Next Steps
- [Rails Sharding Setup](../implementation/rails-sharding-setup.md) - Implementing single-shard-per-request architecture
- [Connection Management](../implementation/connection-management.md) - Managing database connections efficiently