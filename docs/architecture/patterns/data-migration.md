# Data Migration

## Types of Migration

### 1. Schema Migrations (Common)
**Need**: Apply schema changes to all tenant databases

```ruby
# Challenge: Must run on every shard
class AddStatusToTasks < ActiveRecord::Migration[8.0]
  def change
    add_column :tasks, :priority, :string, default: 'medium'
    add_index :tasks, [:organization_id, :priority]
  end
end

# Solution: Migrate all shards
class ShardMigrator
  def self.migrate_all_shards
    Organization.all_shard_names.each do |shard_name|
      puts "Migrating #{shard_name}..."
      ActiveRecord::Base.connected_to(shard: shard_name) do
        ActiveRecord::Base.connection.migration_context.migrate
      end
    end
  end
end
```

### 2. Tenant Rebalancing (Rare)
**Need**: Move organization from one shard to another

```ruby
class TenantMigrator
  def self.move_organization(org_id, from_shard:, to_shard:)
    # 1. Export data from source shard
    data = ActiveRecord::Base.connected_to(shard: from_shard) do
      export_organization_data(org_id)
    end

    # 2. Import data to target shard
    ActiveRecord::Base.connected_to(shard: to_shard) do
      import_organization_data(data)
    end

    # 3. Update shard routing (application-level)
    update_shard_routing(org_id, new_shard: to_shard)

    # 4. Verify migration
    verify_migration(org_id, to_shard)

    # 5. Clean up source data
    ActiveRecord::Base.connected_to(shard: from_shard) do
      cleanup_organization_data(org_id)
    end
  end
end
```

### 3. Data Seeding (Development)
**Need**: Add test data to all shards

```ruby
class ShardSeeder
  def self.seed_all_shards
    Organization.all_shard_names.each do |shard_name|
      ActiveRecord::Base.connected_to(shard: shard_name) do
        Rails.application.load_seed
      end
    end
  end
end
```

## Implementation Requirements

### Schema Migration Runner
```ruby
# lib/shard_migration_runner.rb
class ShardMigrationRunner
  def self.migrate_all
    results = {}

    Organization.all_shard_names.each do |shard_name|
      results[shard_name] = migrate_shard(shard_name)
    end

    report_results(results)
  end

  private

  def self.migrate_shard(shard_name)
    ActiveRecord::Base.connected_to(shard: shard_name) do
      context = ActiveRecord::Base.connection.migration_context
      pending = context.needs_migration?

      if pending
        context.migrate
        { status: :migrated, version: context.current_version }
      else
        { status: :up_to_date, version: context.current_version }
      end
    end
  rescue StandardError => e
    { status: :error, error: e.message }
  end

  def self.report_results(results)
    results.each do |shard, result|
      case result[:status]
      when :migrated
        puts "✓ #{shard}: Migrated to version #{result[:version]}"
      when :up_to_date
        puts "- #{shard}: Already up to date (#{result[:version]})"
      when :error
        puts "✗ #{shard}: ERROR - #{result[:error]}"
      end
    end
  end
end
```

### Rake Tasks
```ruby
# lib/tasks/shard_migrations.rake
namespace :db do
  namespace :shard do
    desc "Migrate all shards"
    task migrate: :environment do
      ShardMigrationRunner.migrate_all
    end

    desc "Check migration status across all shards"
    task status: :environment do
      ShardMigrationRunner.status_all
    end

    desc "Rollback last migration on all shards"
    task rollback: :environment do
      ShardMigrationRunner.rollback_all
    end

    desc "Reset all shard databases"
    task reset: :environment do
      ShardMigrationRunner.reset_all
    end
  end
end
```

## Operational Challenges

### Problem 1: Partial Migration Failures
```ruby
# Some shards migrate successfully, others fail
# Result: Inconsistent schema across shards

# Solution: Rollback strategy
class ShardMigrationRunner
  def self.migrate_all_with_rollback
    successful_shards = []

    Organization.all_shard_names.each do |shard_name|
      begin
        migrate_shard(shard_name)
        successful_shards << shard_name
      rescue StandardError => e
        puts "Migration failed on #{shard_name}: #{e.message}"
        puts "Rolling back successful migrations..."

        successful_shards.each do |rollback_shard|
          rollback_shard(rollback_shard)
        end

        raise "Migration aborted due to failure on #{shard_name}"
      end
    end
  end
end
```

### Problem 2: Long-Running Migrations
```ruby
# Large shards may take hours to migrate
# Solution: Parallel migration with progress tracking

class ParallelShardMigrator
  def self.migrate_all_parallel
    futures = Organization.all_shard_names.map do |shard_name|
      Concurrent::Future.execute do
        puts "Starting migration for #{shard_name}..."
        result = migrate_shard(shard_name)
        puts "Completed migration for #{shard_name}"
        result
      end
    end

    # Wait for all with timeout
    futures.map { |f| f.value(30.minutes) }
  end
end
```

### Problem 3: Zero-Downtime Migrations
```ruby
# Challenge: Migrate without taking application offline
# Solution: Blue-green migration approach

class ZeroDowntimeMigrator
  def self.migrate_with_zero_downtime(migration_class)
    # 1. Create new shard set with new schema
    create_new_shard_set

    # 2. Dual-write to both old and new shards
    enable_dual_write_mode

    # 3. Backfill new shards with existing data
    backfill_new_shards

    # 4. Switch reads to new shards
    switch_reads_to_new_shards

    # 5. Stop dual-write, clean up old shards
    cleanup_old_shards
  end
end
```

## Development Workflow

### Local Development
```ruby
# Simplified for development - single command handles all shards
class Development::ShardManager
  def self.setup
    create_development_shards
    migrate_all_shards
    seed_all_shards
  end

  def self.reset
    drop_all_shards
    setup
  end

  private

  def self.create_development_shards
    %w[shard_0 shard_1 shard_2].each do |shard_name|
      ActiveRecord::Base.connected_to(shard: shard_name.to_sym) do
        ActiveRecord::Base.connection.create_database("development_#{shard_name}")
      end
    end
  end
end
```

### Testing Environment
```ruby
# Each test may need clean shard state
class TestShardManager
  def self.clean_all_shards
    Organization.all_shard_names.each do |shard_name|
      ActiveRecord::Base.connected_to(shard: shard_name) do
        ActiveRecord::Base.connection.execute("DELETE FROM tasks")
        ActiveRecord::Base.connection.execute("DELETE FROM projects")
        ActiveRecord::Base.connection.execute("DELETE FROM users")
        ActiveRecord::Base.connection.execute("DELETE FROM organizations")
      end
    end
  end
end

# In test setup
RSpec.configure do |config|
  config.before(:each) do
    TestShardManager.clean_all_shards
  end
end
```

## Limitations

### Cannot Do
- **Atomic schema changes**: No way to migrate all shards atomically
- **Cross-shard foreign keys**: Cannot maintain referential integrity across shards after migration
- **Instant tenant moves**: Moving tenant data requires downtime or complex dual-write setup

### Must Handle
- **Partial failures**: Some shards may fail migration
- **Long migration times**: Large tenants may take hours to migrate
- **Schema version skew**: Temporary inconsistency during rolling migrations
- **Connection limits**: Parallel migrations consume many database connections

## Monitoring Requirements

```ruby
class MigrationMonitor
  def self.check_schema_consistency
    versions = {}

    Organization.all_shard_names.each do |shard_name|
      versions[shard_name] = get_schema_version(shard_name)
    end

    inconsistent = versions.values.uniq.count > 1

    if inconsistent
      alert_schema_inconsistency(versions)
    end

    versions
  end

  private

  def self.get_schema_version(shard_name)
    ActiveRecord::Base.connected_to(shard: shard_name) do
      ActiveRecord::Base.connection.migration_context.current_version
    end
  rescue StandardError
    :error
  end
end
```

## Next Steps
- [Monitoring & Observability](./monitoring-observability.md) - Tracking shard health
- [Rails Sharding Setup](../implementation/rails-sharding-setup.md) - Implementation details