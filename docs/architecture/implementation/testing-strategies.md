# Testing Strategies

## Testing Philosophy for Sharded Applications

Single-tenant-per-shard architecture simplifies testing because most tests run against a single shard. Focus on testing business logic, not sharding infrastructure.

## Test Database Setup

### RSpec Configuration
```ruby
# spec/rails_helper.rb
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'

RSpec.configure do |config|
  config.use_transactional_fixtures = true

  # Clean all shards before each test
  config.before(:each) do
    clean_all_test_shards
  end

  # Helper methods available in all tests
  config.include ShardingTestHelpers
end

# spec/support/sharding_test_helpers.rb
module ShardingTestHelpers
  def with_shard(shard_name)
    ActiveRecord::Base.connected_to(shard: shard_name) do
      yield
    end
  end

  def clean_all_test_shards
    ShardRouter.all_shard_names.each do |shard_name|
      with_shard(shard_name) do
        DatabaseCleaner.clean
      end
    end

    # Clean shared database
    ActiveRecord::Base.connected_to(database: { writing: :shared }) do
      DatabaseCleaner.clean
    end
  end

  def create_organization_on_shard(organization_id, attributes = {})
    shard_name = ShardRouter.shard_for_organization(organization_id)

    with_shard(shard_name) do
      Organization.create!(attributes.merge(id: organization_id))
    end
  end
end
```

### Database Cleaner Configuration
```ruby
# spec/support/database_cleaner.rb
RSpec.configure do |config|
  config.before(:suite) do
    # Configure database cleaner for all shards
    ShardRouter.all_shard_names.each do |shard_name|
      DatabaseCleaner[:active_record, db: shard_name].strategy = :transaction
    end

    # Configure for shared database
    DatabaseCleaner[:active_record, db: :shared].strategy = :transaction
  end

  config.around(:each) do |example|
    # Clean all shards
    ShardRouter.all_shard_names.each do |shard_name|
      DatabaseCleaner[:active_record, db: shard_name].cleaning do
        # Run example within clean shard
      end
    end

    # Clean shared database
    DatabaseCleaner[:active_record, db: :shared].cleaning do
      example.run
    end
  end
end
```

## Unit Testing (Single Shard)

### Model Tests
```ruby
# spec/models/organization_spec.rb
RSpec.describe Organization, type: :model do
  let(:organization) { create(:organization, id: 123) }

  before do
    # Ensure we're testing on the correct shard
    shard_name = ShardRouter.shard_for_organization(123)
    with_shard(shard_name) do
      organization.save!
    end
  end

  it 'calculates user count correctly' do
    shard_name = ShardRouter.shard_for_organization(organization.id)

    with_shard(shard_name) do
      create_list(:user, 3, organization: organization)
      expect(organization.user_count).to eq(3)
    end
  end
end
```

### Factory Configuration
```ruby
# spec/factories/organizations.rb
FactoryBot.define do
  factory :organization do
    sequence(:id) { |n| n }
    name { "Organization #{id}" }
    plan_type { 'pro' }

    # Helper to create organization on correct shard
    trait :on_shard do
      after(:build) do |org|
        shard_name = ShardRouter.shard_for_organization(org.id)
        ActiveRecord::Base.connected_to(shard: shard_name) do
          org.save! if org.new_record?
        end
      end
    end
  end
end

# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    organization
    sequence(:email) { |n| "user#{n}@example.com" }
    name { "User #{email.split('@').first}" }
    role { 'member' }

    # Automatically create on same shard as organization
    after(:build) do |user|
      if user.organization
        shard_name = ShardRouter.shard_for_organization(user.organization_id)
        ActiveRecord::Base.connected_to(shard: shard_name) do
          user.save! if user.new_record?
        end
      end
    end
  end
end
```

## Integration Testing (Single Shard)

### Controller Tests
```ruby
# spec/controllers/projects_controller_spec.rb
RSpec.describe ProjectsController, type: :controller do
  let(:organization) { create(:organization, id: 456) }
  let(:shard_name) { ShardRouter.shard_for_organization(456) }

  before do
    with_shard(shard_name) do
      organization.save!
      create_list(:project, 3, organization: organization)
    end
  end

  describe 'GET #index' do
    it 'returns projects for the organization' do
      # Request automatically routed to correct shard by middleware
      get :index, params: { organization_id: organization.id }

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response.size).to eq(3)
    end
  end

  describe 'POST #create' do
    it 'creates project on correct shard' do
      project_params = { name: 'New Project', description: 'Test project' }

      expect {
        post :create, params: { organization_id: organization.id, project: project_params }
      }.to change {
        with_shard(shard_name) { Project.count }
      }.by(1)

      expect(response).to have_http_status(:created)
    end
  end
end
```

### Request Tests
```ruby
# spec/requests/api/v1/projects_spec.rb
RSpec.describe 'Projects API', type: :request do
  let(:organization) { create(:organization, id: 789) }
  let(:shard_name) { ShardRouter.shard_for_organization(789) }

  before do
    with_shard(shard_name) do
      organization.save!
    end
  end

  describe 'GET /api/v1/organizations/:organization_id/projects' do
    it 'returns projects from correct shard' do
      # Create test data on correct shard
      with_shard(shard_name) do
        create_list(:project, 2, organization: organization)
      end

      get "/api/v1/organizations/#{organization.id}/projects"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(2)
    end

    it 'handles organization not found' do
      get "/api/v1/organizations/99999/projects"

      expect(response).to have_http_status(:not_found)
    end
  end
end
```

## Cross-Shard Testing

### Admin Controller Tests
```ruby
# spec/controllers/admin/organizations_controller_spec.rb
RSpec.describe Admin::OrganizationsController, type: :controller do
  before do
    # Create organizations on different shards
    [1, 2, 3].each do |org_id|
      shard_name = ShardRouter.shard_for_organization(org_id)
      with_shard(shard_name) do
        create(:organization, id: org_id, name: "Org #{org_id}")
      end
    end
  end

  describe 'GET #index' do
    it 'returns organizations from all shards' do
      get :index

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)
      expect(json_response['organizations'].size).to eq(3)

      org_names = json_response['organizations'].map { |o| o['name'] }
      expect(org_names).to contain_exactly('Org 1', 'Org 2', 'Org 3')
    end

    it 'handles shard failures gracefully' do
      # Mock a shard failure
      allow(ShardRouter).to receive(:all_shard_names).and_return([:shard_0, :nonexistent_shard])

      get :index

      expect(response).to have_http_status(:ok)
      # Should return data from available shards only
    end
  end
end
```

### Cross-Shard Query Tests
```ruby
# spec/lib/cross_tenant_query_spec.rb
RSpec.describe CrossTenantQuery do
  before do
    # Create test data across multiple shards
    [10, 20, 30].each do |org_id|
      shard_name = ShardRouter.shard_for_organization(org_id)
      with_shard(shard_name) do
        org = create(:organization, id: org_id)
        create_list(:user, org_id / 10, organization: org)  # 1, 2, 3 users respectively
      end
    end
  end

  describe '.total_users_across_all_shards' do
    it 'aggregates user counts from all shards' do
      total = CrossTenantQuery.total_users_across_all_shards

      expect(total).to eq(6)  # 1 + 2 + 3
    end
  end

  describe '.all_organizations' do
    it 'returns organizations from all shards' do
      organizations = CrossTenantQuery.all_organizations

      expect(organizations.size).to eq(3)
      expect(organizations.map(&:id)).to contain_exactly(10, 20, 30)
    end
  end
end
```

## Performance Testing

### Shard Distribution Tests
```ruby
# spec/performance/shard_distribution_spec.rb
RSpec.describe 'Shard Distribution' do
  it 'distributes organizations evenly across shards' do
    shard_counts = Hash.new(0)

    # Test distribution with 100 organizations
    (1..100).each do |org_id|
      shard_name = ShardRouter.shard_for_organization(org_id)
      shard_counts[shard_name] += 1
    end

    # Check that distribution is reasonably even
    expect(shard_counts.values.max - shard_counts.values.min).to be <= 2
  end
end
```

### Connection Pool Tests
```ruby
# spec/performance/connection_pool_spec.rb
RSpec.describe 'Connection Pool Performance' do
  it 'does not leak connections' do
    initial_pools = ConnectionPoolMonitor.check_all_pools

    # Simulate many requests
    100.times do |i|
      org_id = i + 1
      shard_name = ShardRouter.shard_for_organization(org_id)

      with_shard(shard_name) do
        Organization.connection.execute('SELECT 1')
      end
    end

    final_pools = ConnectionPoolMonitor.check_all_pools

    # All connections should be returned to pool
    initial_pools.each do |shard, initial_status|
      final_status = final_pools[shard]
      expect(final_status[:checked_out]).to eq(initial_status[:checked_out])
    end
  end
end
```

## Background Job Testing

### Sharded Job Tests
```ruby
# spec/jobs/organization_processing_job_spec.rb
RSpec.describe OrganizationProcessingJob, type: :job do
  let(:organization) { create(:organization, id: 555) }
  let(:shard_name) { ShardRouter.shard_for_organization(555) }

  before do
    with_shard(shard_name) do
      organization.save!
    end
  end

  it 'processes organization on correct shard' do
    expect {
      described_class.perform_now(organization.id)
    }.to change {
      with_shard(shard_name) do
        organization.reload.processed?
      end
    }.from(false).to(true)
  end

  it 'handles missing organization gracefully' do
    expect {
      described_class.perform_now(99999)
    }.not_to raise_error
  end
end
```

## Error Handling Tests

### Shard Failure Tests
```ruby
# spec/middleware/sharding_middleware_spec.rb
RSpec.describe ShardingMiddleware do
  let(:app) { double('app') }
  let(:middleware) { described_class.new(app) }

  describe 'shard failure handling' do
    it 'returns 503 when shard is unavailable' do
      env = {
        'REQUEST_METHOD' => 'GET',
        'PATH_INFO' => '/api/v1/organizations/123/projects'
      }

      # Mock shard connection failure
      allow(ActiveRecord::Base).to receive(:connected_to)
        .and_raise(ActiveRecord::ConnectionNotEstablished.new('Connection failed'))

      status, headers, body = middleware.call(env)

      expect(status).to eq(503)
      expect(headers['Content-Type']).to eq('application/json')

      response = JSON.parse(body.first)
      expect(response['error']['code']).to eq('SHARD_OFFLINE')
    end
  end
end
```

## Test Utilities

### Custom Matchers
```ruby
# spec/support/custom_matchers.rb
RSpec::Matchers.define :exist_on_shard do |shard_name|
  match do |record|
    ActiveRecord::Base.connected_to(shard: shard_name) do
      record.class.exists?(record.id)
    end
  end

  failure_message do |record|
    "expected #{record.class}(#{record.id}) to exist on #{shard_name}"
  end
end

# Usage in tests
expect(organization).to exist_on_shard(:shard_1)
```

### Test Data Builders
```ruby
# spec/support/shard_test_builder.rb
class ShardTestBuilder
  def self.create_distributed_data
    # Create organizations across different shards
    organizations = [
      { id: 1, name: 'Small Org', users: 5, projects: 2 },
      { id: 2, name: 'Medium Org', users: 25, projects: 10 },
      { id: 3, name: 'Large Org', users: 100, projects: 50 }
    ]

    organizations.each do |org_data|
      shard_name = ShardRouter.shard_for_organization(org_data[:id])

      ActiveRecord::Base.connected_to(shard: shard_name) do
        org = Organization.create!(id: org_data[:id], name: org_data[:name])
        create_list(:user, org_data[:users], organization: org)
        create_list(:project, org_data[:projects], organization: org)
      end
    end
  end

  def self.clean_distributed_data
    ShardRouter.all_shard_names.each do |shard_name|
      ActiveRecord::Base.connected_to(shard: shard_name) do
        [Task, Project, User, Organization].each(&:delete_all)
      end
    end
  end
end
```

## Best Practices

### 1. Test Business Logic, Not Sharding
```ruby
# Good: Test the business logic
it 'creates project with correct attributes' do
  project = create(:project, name: 'Test Project')
  expect(project.name).to eq('Test Project')
  expect(project.status).to eq('active')
end

# Avoid: Testing sharding infrastructure
it 'creates project on correct shard' do
  # This is testing framework behavior, not business logic
end
```

### 2. Use Explicit Shard Context
```ruby
# Good: Explicit about which shard you're testing
describe 'user creation' do
  let(:organization) { create(:organization, id: 123) }
  let(:shard_name) { ShardRouter.shard_for_organization(123) }

  it 'creates user on organization shard' do
    with_shard(shard_name) do
      user = create(:user, organization: organization)
      expect(User.find(user.id)).to eq(user)
    end
  end
end
```

### 3. Test Cross-Shard Operations Explicitly
```ruby
# Test cross-shard operations in dedicated specs
describe 'Cross-Shard Operations' do
  before { create_distributed_test_data }
  after { clean_distributed_test_data }

  it 'aggregates data across all shards' do
    result = AdminService.platform_statistics
    expect(result[:total_organizations]).to eq(3)
  end
end
```

## Limitations

### Cannot Test
- **Distributed transactions**: Don't exist in our model
- **Cross-shard referential integrity**: Enforced at application level
- **Real shard failure scenarios**: Hard to simulate in tests

### Must Test
- **Business logic within shards**: Core application functionality
- **Cross-shard aggregation logic**: Admin and reporting features
- **Error handling**: Graceful degradation when shards unavailable
- **Data consistency**: Within single shard boundaries

## Next Steps
- [Architecture Decision Records](../decisions/) - Document testing decisions
- [Examples](../examples/) - See real test examples from our Rails app