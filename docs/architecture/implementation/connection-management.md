# Connection Management

## Single-Shard-Per-Request Connection Strategy

Each request connects to exactly one shard database. This simplifies connection management and ensures predictable resource usage.

## Connection Pool Configuration

### Basic Setup
```ruby
# config/database.yml - Configure pools per shard
default: &default
  adapter: sqlite3
  pool: 5  # 5 connections per shard
  timeout: 5000
  checkout_timeout: 5

development:
  primary:
    <<: *default
    database: db/development.sqlite3

  shard_0:
    <<: *default
    database: db/development_shard_0.sqlite3
    pool: 10  # Larger pool if this shard has more traffic

  shard_1:
    <<: *default
    database: db/development_shard_1.sqlite3
    pool: 5

  shard_2:
    <<: *default
    database: db/development_shard_2.sqlite3
    pool: 15  # Much larger pool for heavy tenant
```

### Production Considerations
```ruby
# For PostgreSQL/MySQL in production
production:
  shard_0:
    adapter: postgresql
    url: <%= ENV['SHARD_0_DATABASE_URL'] %>
    pool: <%= ENV.fetch('RAILS_MAX_THREADS', 5) %>
    checkout_timeout: 5
    # Connection limits based on database server capacity

  shard_1:
    adapter: postgresql
    url: <%= ENV['SHARD_1_DATABASE_URL'] %>
    pool: <%= ENV.fetch('RAILS_MAX_THREADS', 5) %>
    checkout_timeout: 5
```

## Connection Lifecycle

### Request Lifecycle
```ruby
class ShardingMiddleware
  def call(env)
    request = Rack::Request.new(env)
    organization_id = extract_organization_id(request)

    if organization_id
      shard_name = ShardRouter.shard_for_organization(organization_id)

      # Single connection acquired for entire request
      ActiveRecord::Base.connected_to(shard: shard_name) do
        @app.call(env)
      end
      # Connection automatically returned to pool
    else
      @app.call(env)
    end
  end
end
```

### Background Job Lifecycle
```ruby
class TenantSpecificJob < ApplicationJob
  def perform(organization_id)
    shard_name = ShardRouter.shard_for_organization(organization_id)

    # Single connection for entire job
    ActiveRecord::Base.connected_to(shard: shard_name) do
      organization = Organization.find(organization_id)
      process_organization_data(organization)
    end
    # Connection returned when job completes
  end
end
```

## Connection Pool Monitoring

### Pool Status Tracking
```ruby
class ConnectionPoolMonitor
  def self.check_all_pools
    status = {}

    ShardRouter.all_shard_names.each do |shard_name|
      begin
        pool = ActiveRecord::Base.connection_handler.retrieve_connection_pool(
          shard_name.to_s,
          role: :writing,
          shard: shard_name
        )

        status[shard_name] = {
          size: pool.size,
          checked_out: pool.checked_out.count,
          available: pool.available.count,
          utilization: (pool.checked_out.count.to_f / pool.size * 100).round(2)
        }
      rescue StandardError => e
        status[shard_name] = { error: e.message }
      end
    end

    status
  end
end
```

### Health Check Integration
```ruby
class HealthController < ApplicationController
  def shards
    pool_status = ConnectionPoolMonitor.check_all_pools

    render json: {
      timestamp: Time.current,
      connection_pools: pool_status,
      warnings: generate_warnings(pool_status)
    }
  end

  private

  def generate_warnings(status)
    warnings = []

    status.each do |shard, info|
      next if info[:error]

      if info[:utilization] > 80
        warnings << "#{shard}: High connection utilization (#{info[:utilization]}%)"
      end

      if info[:available] == 0
        warnings << "#{shard}: No available connections"
      end
    end

    warnings
  end
end
```

## Connection Optimization

### Connection Reuse
```ruby
# Good: Single connection per request (handled by middleware)
def index
  # Uses same connection throughout request
  @organization = Organization.find(params[:organization_id])
  @projects = @organization.projects.includes(:tasks)
  @users = @organization.users.active
end

# Bad: Multiple connection acquisitions (don't do this)
def index_bad
  ActiveRecord::Base.connected_to(shard: shard_name) do
    @organization = Organization.find(params[:organization_id])
  end

  ActiveRecord::Base.connected_to(shard: shard_name) do
    @projects = Project.where(organization_id: params[:organization_id])
  end
  # Inefficient - acquires connection multiple times
end
```

### Lazy Connection Loading
```ruby
# Don't establish connections to all shards at startup
# Only connect when needed

class ShardConnectionManager
  def self.establish_shard_connection(shard_name)
    return if connection_exists?(shard_name)

    config = Rails.application.config.database_configuration[Rails.env][shard_name.to_s]
    ActiveRecord::Base.connection_handler.establish_connection(config, shard: shard_name)
  end

  private

  def self.connection_exists?(shard_name)
    ActiveRecord::Base.connection_handler.connected?(shard_name.to_s, role: :writing, shard: shard_name)
  end
end
```

## Error Handling

### Connection Timeout Handling
```ruby
class ShardingMiddleware
  def call(env)
    request = Rack::Request.new(env)
    organization_id = extract_organization_id(request)

    if organization_id
      shard_name = ShardRouter.shard_for_organization(organization_id)

      begin
        ActiveRecord::Base.connected_to(shard: shard_name) do
          @app.call(env)
        end
      rescue ActiveRecord::ConnectionTimeoutError => e
        Rails.logger.error "Connection timeout for shard #{shard_name}: #{e.message}"

        [503, { 'Content-Type' => 'application/json' },
         [{ error: 'Service temporarily unavailable', shard: shard_name }.to_json]]
      end
    else
      @app.call(env)
    end
  end
end
```

### Connection Recovery
```ruby
class ShardConnectionRecovery
  def self.recover_failed_connection(shard_name)
    begin
      # Test connection
      ActiveRecord::Base.connected_to(shard: shard_name) do
        ActiveRecord::Base.connection.execute('SELECT 1')
      end
    rescue StandardError => e
      Rails.logger.warn "Recovering failed connection for #{shard_name}: #{e.message}"

      # Clear existing connections
      ActiveRecord::Base.connection_handler.remove_connection_pool(
        shard_name.to_s,
        role: :writing,
        shard: shard_name
      )

      # Re-establish connection
      ShardConnectionManager.establish_shard_connection(shard_name)
    end
  end
end
```

## Cross-Shard Connection Strategy

### Parallel Connection Management
```ruby
class CrossShardQueryManager
  def self.query_all_shards_parallel(timeout: 30.seconds)
    futures = ShardRouter.all_shard_names.map do |shard_name|
      Concurrent::Future.execute do
        begin
          ActiveRecord::Base.connected_to(shard: shard_name) do
            yield(shard_name)
          end
        rescue StandardError => e
          Rails.logger.error "Failed to query #{shard_name}: #{e.message}"
          nil
        end
      end
    end

    # Wait for all with timeout
    results = futures.map { |f| f.value(timeout) }.compact
    results
  end
end
```

### Connection Limits for Cross-Shard Operations
```ruby
# Limit concurrent cross-shard operations to prevent connection exhaustion
class CrossShardConnectionLimiter
  MAX_CONCURRENT_SHARDS = 5

  def self.query_shards_with_limit(shard_names, &block)
    results = []

    shard_names.each_slice(MAX_CONCURRENT_SHARDS) do |shard_batch|
      batch_results = shard_batch.map do |shard_name|
        Thread.new do
          ActiveRecord::Base.connected_to(shard: shard_name) do
            block.call(shard_name)
          end
        end
      end.map(&:value)

      results.concat(batch_results.compact)
    end

    results
  end
end
```

## Performance Considerations

### Connection Pool Sizing
```ruby
# Rule of thumb: Pool size = (Web server threads) + (Background job concurrency)
# Example: Puma with 5 threads + 3 Sidekiq workers = 8 connections minimum

# config/database.yml
production:
  shard_0:
    pool: <%= ENV.fetch('RAILS_MAX_THREADS', 5).to_i + ENV.fetch('SIDEKIQ_CONCURRENCY', 3).to_i %>
```

### Connection Warmup
```ruby
# Warm up connections on application startup
class ConnectionWarmer
  def self.warm_all_shards
    ShardRouter.all_shard_names.each do |shard_name|
      begin
        ActiveRecord::Base.connected_to(shard: shard_name) do
          ActiveRecord::Base.connection.execute('SELECT 1')
        end
        Rails.logger.info "Warmed connection for #{shard_name}"
      rescue StandardError => e
        Rails.logger.error "Failed to warm #{shard_name}: #{e.message}"
      end
    end
  end
end

# In config/initializers/sharding.rb
Rails.application.config.after_initialize do
  ConnectionWarmer.warm_all_shards
end
```

## Memory Management

### Connection Object Lifecycle
```ruby
# Monitor connection objects to prevent memory leaks
class ConnectionMemoryMonitor
  def self.check_connection_memory
    ObjectSpace.each_object(ActiveRecord::ConnectionAdapters::AbstractAdapter).map do |conn|
      {
        class: conn.class.name,
        object_id: conn.object_id,
        pool_size: conn.pool&.size,
        active: conn.active?
      }
    end
  end
end
```

### Garbage Collection Considerations
```ruby
# In production, force GC after heavy cross-shard operations
class CrossShardOperation
  def self.platform_wide_analysis
    results = query_all_shards_parallel do |shard_name|
      # Heavy computation across all shards
    end

    # Force GC to clean up connection objects
    GC.start

    results
  end
end
```

## Limitations

### Cannot Do
- **Connection sharing across shards**: Each shard needs its own connection
- **Global transactions**: Cannot span multiple database connections
- **Instant failover**: Connection recovery takes time

### Must Monitor
- **Pool utilization per shard**: Some shards may be busier
- **Connection leaks**: Failed requests may not return connections
- **Memory usage**: Connection objects consume memory

## Troubleshooting

### Connection Pool Exhaustion
```ruby
# Symptoms: ActiveRecord::ConnectionTimeoutError
# Solutions:
1. Increase pool size for busy shards
2. Reduce request timeout
3. Add connection monitoring alerts
4. Check for connection leaks in background jobs
```

### Shard Unavailability
```ruby
# Symptoms: Connection refused errors
# Solutions:
1. Implement circuit breaker pattern
2. Add connection retry logic
3. Graceful degradation for cross-shard operations
4. Health check monitoring
```

## Next Steps
- [Middleware & Routing](./middleware-routing.md) - Request routing implementation
- [Testing Strategies](./testing-strategies.md) - Testing connection management