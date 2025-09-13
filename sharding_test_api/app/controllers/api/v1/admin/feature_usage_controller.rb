class Api::V1::Admin::FeatureUsageController < Api::V1::Admin::BaseController
  def index
    # Feature usage is stored on primary database (cross-tenant)

    # Date range for analysis
    start_date = params[:start_date]&.to_date || 30.days.ago.to_date
    end_date = params[:end_date]&.to_date || Date.current

    # Get feature usage data
    usage_scope = FeatureUsage.includes(:organization)
                              .where(date: start_date..end_date)

    # Apply organization filter if specified
    usage_scope = usage_scope.where(organization_id: params[:organization_id]) if params[:organization_id]

    # Generate different views of the data
    feature_summary = generate_feature_summary(usage_scope)
    organization_summary = generate_organization_summary(usage_scope)
    daily_trends = generate_daily_trends(usage_scope, start_date, end_date)
    top_features = generate_top_features(usage_scope)

    render json: {
      date_range: {
        start_date: start_date,
        end_date: end_date
      },
      summary: {
        total_organizations: usage_scope.distinct.count(:organization_id),
        total_features_tracked: usage_scope.distinct.count(:feature_name),
        total_usage_events: usage_scope.sum(:usage_count)
      },
      feature_summary: feature_summary,
      organization_summary: organization_summary,
      daily_trends: daily_trends,
      top_features: top_features
    }
  end

  private

  def generate_feature_summary(scope)
    scope.group(:feature_name)
         .sum(:usage_count)
         .sort_by { |_, count| -count }
         .to_h
  end

  def generate_organization_summary(scope)
    scope.joins(:organization)
         .group('organizations.name')
         .sum(:usage_count)
         .sort_by { |_, count| -count }
         .first(20) # Top 20 organizations
         .to_h
  end

  def generate_daily_trends(scope, start_date, end_date)
    scope.group(:date, :feature_name)
         .sum(:usage_count)
         .group_by { |(date, _), _| date }
         .transform_values do |day_data|
           day_data.transform_keys { |(_, feature), _| feature }
                   .transform_values { |count| count }
         end
         .sort
         .to_h
  end

  def generate_top_features(scope)
    scope.group(:feature_name)
         .group('organizations.name')
         .joins(:organization)
         .sum(:usage_count)
         .group_by { |(feature, _), _| feature }
         .transform_values do |org_data|
           org_data.transform_keys { |(_, org), _| org }
                   .sort_by { |_, count| -count }
                   .first(5) # Top 5 organizations per feature
                   .to_h
         end
  end
end