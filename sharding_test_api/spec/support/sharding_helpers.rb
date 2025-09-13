module ShardingHelpers
  # Helper methods for testing sharding functionality

  def with_shard(shard_name)
    ActiveRecord::Base.connected_to(shard: shard_name) do
      yield
    end
  end

  def shard_for_organization(org_id)
    ApplicationRecord.shard_for_organization(org_id)
  end

  def create_organization_on_shard(org_id, attributes = {})
    shard = shard_for_organization(org_id)
    with_shard(shard) do
      Organization.create!(attributes.merge(id: org_id))
    end
  end

  def clear_all_shards
    shard_count = Rails.application.config.sharding.shard_count
    (0...shard_count).each do |shard_number|
      shard_name = "shard_#{shard_number}".to_sym
      begin
        with_shard(shard_name) do
          Task.delete_all
          Project.delete_all
          User.delete_all
          Organization.delete_all
        end
      rescue ActiveRecord::DatabaseConnectionError
        # Shard may not be available
      end
    end
  end
end

RSpec.configure do |config|
  config.include ShardingHelpers
end