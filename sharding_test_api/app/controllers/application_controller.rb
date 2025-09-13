class ApplicationController < ActionController::API
  # Basic API controller functionality
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from ActiveRecord::RecordInvalid, with: :record_invalid

  private

  def record_not_found(exception)
    render json: { error: "Record not found" }, status: :not_found
  end

  def record_invalid(exception)
    render json: { error: exception.message, details: exception.record.errors.full_messages }, status: :unprocessable_entity
  end

  def organization_id
    params[:organization_id]
  end
end