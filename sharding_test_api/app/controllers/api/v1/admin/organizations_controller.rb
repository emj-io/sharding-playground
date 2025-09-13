class Api::V1::Admin::OrganizationsController < Api::V1::Admin::BaseController
  def index
    organizations = organizations_with_stats

    # Sort by creation date or name
    organizations.sort_by! { |org| org['created_at'] }

    # Add platform-wide statistics
    total_stats = {
      total_organizations: organizations.count,
      total_users: organizations.sum { |org| org['user_count'] },
      total_projects: organizations.sum { |org| org['project_count'] },
      total_tasks: organizations.sum { |org| org['task_count'] },
      plan_distribution: organizations.group_by { |org| org['plan_type'] }.transform_values(&:count)
    }

    render json: {
      organizations: organizations,
      statistics: total_stats
    }
  end

  def show
    organization = Organization.find(params[:id])

    # Get detailed stats for this organization
    detailed_stats = {
      users: organization.users.group(:role).count,
      projects: organization.projects.group(:status).count,
      tasks: organization.tasks.group(:status).count,
      recent_activity: recent_activity_for_organization(organization.id)
    }

    render json: organization.as_json.merge(
      detailed_stats: detailed_stats
    )
  end

  private

  def recent_activity_for_organization(org_id)
    AuditLog.where(organization_id: org_id)
            .recent
            .limit(10)
            .select(:action, :resource_type, :created_at)
  end
end