class Api::V1::Admin::BaseController < ApplicationController
  # Admin operations for cross-tenant analytics

  private

  # Get organizations with their stats (simplified for non-sharded version)
  def organizations_with_stats
    Organization.all.map do |org|
      org.as_json.merge(
        user_count: org.user_count,
        project_count: org.project_count,
        task_count: org.task_count
      )
    end
  end
end