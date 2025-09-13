class Api::V1::Admin::AuditLogsController < Api::V1::Admin::BaseController
  def index
    # Audit logs are stored on primary database (cross-tenant)
    @audit_logs = AuditLog.includes(:organization, :user)
                          .recent

    # Apply filters
    @audit_logs = @audit_logs.where(organization_id: params[:organization_id]) if params[:organization_id]
    @audit_logs = @audit_logs.by_action(params[:action]) if params[:action]
    @audit_logs = @audit_logs.where('created_at >= ?', params[:start_date]) if params[:start_date]
    @audit_logs = @audit_logs.where('created_at <= ?', params[:end_date]) if params[:end_date]

    # Pagination
    page = params[:page]&.to_i || 1
    per_page = params[:per_page]&.to_i || 50
    per_page = [per_page, 1000].min # Cap at 1000

    @audit_logs = @audit_logs.limit(per_page).offset((page - 1) * per_page)

    # Generate summary statistics
    summary_stats = generate_audit_summary(params)

    render json: {
      audit_logs: @audit_logs.map { |log| audit_log_with_details(log) },
      pagination: {
        page: page,
        per_page: per_page,
        total_count: AuditLog.count # This could be expensive with large datasets
      },
      summary: summary_stats
    }
  end

  def show
    @audit_log = AuditLog.find(params[:id])
    render json: audit_log_with_details(@audit_log)
  end

  private

  def audit_log_with_details(log)
    log.as_json(include: {
      organization: { only: [:id, :name] },
      user: { only: [:id, :name, :email] }
    })
  end

  def generate_audit_summary(filter_params)
    scope = AuditLog.all
    scope = scope.where(organization_id: filter_params[:organization_id]) if filter_params[:organization_id]
    scope = scope.where('created_at >= ?', filter_params[:start_date]) if filter_params[:start_date]
    scope = scope.where('created_at <= ?', filter_params[:end_date]) if filter_params[:end_date]

    {
      total_events: scope.count,
      events_by_action: scope.group(:action).count,
      events_by_resource_type: scope.group(:resource_type).count,
      events_by_organization: scope.joins(:organization).group('organizations.name').count.first(10),
      recent_24h: scope.where('created_at >= ?', 24.hours.ago).count
    }
  end
end