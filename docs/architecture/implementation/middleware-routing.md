# Middleware & Routing

## Request Routing Strategy

Every request must be routed to exactly one shard based on the organization ID in the URL. The middleware handles this transparently.

## Core Middleware Implementation

### Sharding Middleware
```ruby
# app/middleware/sharding_middleware.rb
class ShardingMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    organization_id = extract_organization_id(request)

    if organization_id
      route_to_shard(organization_id, env)
    else
      handle_non_tenant_request(env)
    end
  end

  private

  def extract_organization_id(request)
    # Pattern: /api/v1/organizations/123/...
    if match = request.path.match(%r{/api/v1/organizations/(\d+)})
      match[1].to_i
    end
  end

  def route_to_shard(organization_id, env)
    shard_name = ShardRouter.shard_for_organization(organization_id)

    # Set shard context for entire request
    env['sharding.shard_name'] = shard_name
    env['sharding.organization_id'] = organization_id

    ActiveRecord::Base.connected_to(shard: shard_name) do
      @app.call(env)
    end
  rescue ActiveRecord::ConnectionNotEstablished => e
    render_shard_unavailable_error(shard_name, e)
  end

  def handle_non_tenant_request(env)
    # Health checks, admin endpoints that don't require organization context
    @app.call(env)
  end

  def render_shard_unavailable_error(shard_name, error)
    Rails.logger.error "Shard #{shard_name} unavailable: #{error.message}"

    [503,
     { 'Content-Type' => 'application/json' },
     [{
       error: 'Service temporarily unavailable',
       message: 'The requested organization data is currently unavailable',
       shard: shard_name
     }.to_json]]
  end
end
```

### Enhanced Router with Caching
```ruby
# app/lib/shard_router.rb
class ShardRouter
  SHARD_COUNT = ENV.fetch('SHARD_COUNT', 3).to_i

  # Cache organization -> shard mappings to reduce computation
  @org_shard_cache = {}
  @cache_mutex = Mutex.new

  def self.shard_for_organization(organization_id)
    @cache_mutex.synchronize do
      @org_shard_cache[organization_id] ||= calculate_shard(organization_id)
    end
  end

  def self.clear_cache!
    @cache_mutex.synchronize do
      @org_shard_cache.clear
    end
  end

  def self.all_shard_names
    (0...SHARD_COUNT).map { |i| "shard_#{i}".to_sym }
  end

  private

  def self.calculate_shard(organization_id)
    shard_number = organization_id.to_i % SHARD_COUNT
    "shard_#{shard_number}".to_sym
  end
end
```

## URL Pattern Matching

### Organization ID Extraction
```ruby
module OrganizationExtractor
  # Standard tenant-scoped endpoints
  TENANT_PATTERNS = [
    %r{/api/v1/organizations/(\d+)/users},
    %r{/api/v1/organizations/(\d+)/projects},
    %r{/api/v1/organizations/(\d+)/tasks}
  ].freeze

  # Background job patterns (if using URL-based job identification)
  JOB_PATTERNS = [
    %r{/jobs/organization/(\d+)/}
  ].freeze

  def self.extract_from_path(path)
    ALL_PATTERNS = TENANT_PATTERNS + JOB_PATTERNS

    ALL_PATTERNS.each do |pattern|
      if match = path.match(pattern)
        return match[1].to_i
      end
    end

    nil
  end

  def self.tenant_scoped_path?(path)
    extract_from_path(path).present?
  end
end
```

### Alternative: Header-Based Routing
```ruby
# For APIs that use headers instead of URL parameters
class HeaderBasedShardingMiddleware
  def call(env)
    request = Rack::Request.new(env)

    # Extract organization ID from header
    organization_id = request.get_header('HTTP_X_ORGANIZATION_ID')&.to_i

    if organization_id
      shard_name = ShardRouter.shard_for_organization(organization_id)

      ActiveRecord::Base.connected_to(shard: shard_name) do
        @app.call(env)
      end
    else
      @app.call(env)
    end
  end
end
```

## Request Context Management

### Shard Context Storage
```ruby
# Store shard context for use throughout request
class ShardContext
  def self.current_shard
    RequestStore.store[:current_shard]
  end

  def self.current_organization_id
    RequestStore.store[:current_organization_id]
  end

  def self.set_context(shard_name, organization_id)
    RequestStore.store[:current_shard] = shard_name
    RequestStore.store[:current_organization_id] = organization_id
  end

  def self.clear_context
    RequestStore.store[:current_shard] = nil
    RequestStore.store[:current_organization_id] = nil
  end
end

# Enhanced middleware with context
class ShardingMiddleware
  def route_to_shard(organization_id, env)
    shard_name = ShardRouter.shard_for_organization(organization_id)

    # Set context for request
    ShardContext.set_context(shard_name, organization_id)

    ActiveRecord::Base.connected_to(shard: shard_name) do
      @app.call(env)
    end
  ensure
    ShardContext.clear_context
  end
end
```

### Request Logging Integration
```ruby
class ShardingMiddleware
  def call(env)
    request = Rack::Request.new(env)
    organization_id = extract_organization_id(request)

    if organization_id
      shard_name = ShardRouter.shard_for_organization(organization_id)

      # Add shard info to logs for entire request
      Rails.logger.tagged("shard:#{shard_name}", "org:#{organization_id}") do
        ActiveRecord::Base.connected_to(shard: shard_name) do
          @app.call(env)
        end
      end
    else
      @app.call(env)
    end
  end
end
```

## Error Handling

### Shard-Specific Error Responses
```ruby
class ShardingMiddleware
  private

  def handle_shard_error(shard_name, error, env)
    case error
    when ActiveRecord::ConnectionNotEstablished
      render_shard_offline_error(shard_name)
    when ActiveRecord::ConnectionTimeoutError
      render_shard_timeout_error(shard_name)
    when ActiveRecord::StatementInvalid
      render_shard_query_error(shard_name, error)
    else
      render_generic_shard_error(shard_name, error)
    end
  end

  def render_shard_offline_error(shard_name)
    [503, json_headers, [error_response(
      code: 'SHARD_OFFLINE',
      message: 'The organization data is temporarily unavailable',
      shard: shard_name
    )]]
  end

  def render_shard_timeout_error(shard_name)
    [504, json_headers, [error_response(
      code: 'SHARD_TIMEOUT',
      message: 'The organization data request timed out',
      shard: shard_name
    )]]
  end

  def json_headers
    { 'Content-Type' => 'application/json' }
  end

  def error_response(code:, message:, shard: nil)
    {
      error: {
        code: code,
        message: message,
        shard: shard,
        timestamp: Time.current.iso8601
      }
    }.to_json
  end
end
```

### Circuit Breaker Pattern
```ruby
class ShardCircuitBreaker
  FAILURE_THRESHOLD = 5
  TIMEOUT_PERIOD = 30.seconds

  def self.call_with_circuit_breaker(shard_name)
    state = get_circuit_state(shard_name)

    case state[:status]
    when :closed
      execute_with_failure_tracking(shard_name) { yield }
    when :open
      if state[:opened_at] < TIMEOUT_PERIOD.ago
        # Try to close circuit
        set_circuit_state(shard_name, :half_open)
        execute_with_failure_tracking(shard_name) { yield }
      else
        raise ShardUnavailableError, "Circuit breaker open for #{shard_name}"
      end
    when :half_open
      execute_with_failure_tracking(shard_name) { yield }
    end
  end

  private

  def self.execute_with_failure_tracking(shard_name)
    yield.tap do
      # Success - reset failure count
      reset_failure_count(shard_name)
      set_circuit_state(shard_name, :closed) if get_circuit_state(shard_name)[:status] == :half_open
    end
  rescue StandardError => e
    increment_failure_count(shard_name)

    if get_failure_count(shard_name) >= FAILURE_THRESHOLD
      set_circuit_state(shard_name, :open)
    end

    raise
  end

  def self.get_circuit_state(shard_name)
    Rails.cache.fetch("circuit_breaker:#{shard_name}", expires_in: 1.hour) do
      { status: :closed, failure_count: 0, opened_at: nil }
    end
  end

  def self.set_circuit_state(shard_name, status)
    state = get_circuit_state(shard_name)
    state[:status] = status
    state[:opened_at] = Time.current if status == :open
    Rails.cache.write("circuit_breaker:#{shard_name}", state, expires_in: 1.hour)
  end
end
```

## Performance Optimization

### Route Caching
```ruby
class CachingShardRouter
  CACHE_TTL = 1.hour

  def self.shard_for_organization(organization_id)
    Rails.cache.fetch("shard_route:#{organization_id}", expires_in: CACHE_TTL) do
      calculate_shard_for_organization(organization_id)
    end
  end

  def self.warm_cache_for_active_organizations
    # Pre-populate cache for frequently accessed organizations
    active_org_ids = get_active_organization_ids

    active_org_ids.each do |org_id|
      shard_for_organization(org_id)  # Populates cache
    end
  end

  private

  def self.calculate_shard_for_organization(organization_id)
    shard_number = organization_id.to_i % SHARD_COUNT
    "shard_#{shard_number}".to_sym
  end
end
```

### Request Filtering
```ruby
class ShardingMiddleware
  # Skip sharding for certain paths
  SKIP_PATHS = [
    '/health',
    '/api/v1/admin',
    '/metrics',
    '/favicon.ico'
  ].freeze

  def call(env)
    request = Rack::Request.new(env)

    # Quick path filtering
    if skip_sharding?(request.path)
      return @app.call(env)
    end

    # Normal sharding logic
    organization_id = extract_organization_id(request)
    # ... rest of implementation
  end

  private

  def skip_sharding?(path)
    SKIP_PATHS.any? { |skip_path| path.start_with?(skip_path) }
  end
end
```

## Background Job Integration

### Job-Level Sharding
```ruby
# Extend ActiveJob to support sharding
module ShardedJob
  extend ActiveSupport::Concern

  included do
    around_perform :with_organization_shard
  end

  private

  def with_organization_shard
    organization_id = arguments.first

    if organization_id.is_a?(Integer)
      shard_name = ShardRouter.shard_for_organization(organization_id)

      ActiveRecord::Base.connected_to(shard: shard_name) do
        yield
      end
    else
      yield
    end
  end
end

# Usage in job classes
class ProcessOrganizationDataJob < ApplicationJob
  include ShardedJob

  def perform(organization_id, data_type)
    # This automatically uses the correct shard
    organization = Organization.find(organization_id)
    organization.process_data(data_type)
  end
end
```

### Queue-Based Sharding
```ruby
# Route jobs to shard-specific queues
class ShardedJobRouter
  def self.enqueue_for_organization(job_class, organization_id, *args)
    shard_name = ShardRouter.shard_for_organization(organization_id)
    queue_name = "#{shard_name}_queue"

    job_class.set(queue: queue_name).perform_later(organization_id, *args)
  end
end

# Worker configuration (Sidekiq example)
# config/sidekiq.yml
:queues:
  - shard_0_queue
  - shard_1_queue
  - shard_2_queue
  - default
```

## Monitoring Integration

### Request Metrics
```ruby
class ShardingMiddleware
  def call(env)
    start_time = Time.current

    begin
      response = route_request(env)
      record_success_metrics(env, start_time)
      response
    rescue StandardError => e
      record_error_metrics(env, e, start_time)
      raise
    end
  end

  private

  def record_success_metrics(env, start_time)
    duration = (Time.current - start_time) * 1000
    shard_name = env['sharding.shard_name']

    if shard_name
      Rails.logger.info({
        event: 'shard_request_success',
        shard: shard_name,
        organization_id: env['sharding.organization_id'],
        duration_ms: duration,
        path: env['PATH_INFO']
      })

      # Send to metrics service
      ShardMetrics.record_request_duration(shard_name, duration)
    end
  end

  def record_error_metrics(env, error, start_time)
    duration = (Time.current - start_time) * 1000
    shard_name = env['sharding.shard_name']

    Rails.logger.error({
      event: 'shard_request_error',
      shard: shard_name,
      organization_id: env['sharding.organization_id'],
      error_class: error.class.name,
      error_message: error.message,
      duration_ms: duration,
      path: env['PATH_INFO']
    })

    ShardMetrics.record_request_error(shard_name, error.class.name)
  end
end
```

## Testing Support

### Test Middleware
```ruby
# Test helper for simulating shard routing
class TestShardingMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    # In tests, allow overriding shard via header
    if test_shard = env['HTTP_X_TEST_SHARD']
      ActiveRecord::Base.connected_to(shard: test_shard.to_sym) do
        @app.call(env)
      end
    else
      # Use normal sharding logic
      ShardingMiddleware.new(@app).call(env)
    end
  end
end
```

### Test Helpers
```ruby
module ShardingTestHelpers
  def with_test_shard(shard_name)
    old_shard = @current_test_shard
    @current_test_shard = shard_name

    ActiveRecord::Base.connected_to(shard: shard_name) do
      yield
    end
  ensure
    @current_test_shard = old_shard
  end

  def get_with_shard(path, shard_name)
    get path, headers: { 'HTTP_X_TEST_SHARD' => shard_name }
  end
end
```

## Next Steps
- [Testing Strategies](./testing-strategies.md) - Testing sharded applications
- [Shard Key Selection](../patterns/shard-key-selection.md) - Optimizing routing strategies