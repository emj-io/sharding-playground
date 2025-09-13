class Api::V1::BaseController < ApplicationController
  before_action :set_organization

  private

  def set_organization
    @organization = Organization.find(params[:organization_id]) if params[:organization_id]
  end

  def ensure_organization
    return if @organization

    render json: { error: 'Organization required' }, status: :bad_request
  end


  def log_audit(action, resource, metadata = {})
    AuditLog.log_action(
      organization: @organization,
      user: nil, # Would be current_user in real app
      action: action,
      resource: resource,
      metadata: metadata
    )
  end

  def track_feature_usage(feature_name)
    FeatureUsage.increment_usage(
      organization: @organization,
      feature_name: feature_name
    )
  end
end