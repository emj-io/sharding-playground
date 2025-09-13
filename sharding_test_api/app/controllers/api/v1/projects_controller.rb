class Api::V1::ProjectsController < Api::V1::BaseController
  before_action :ensure_organization
  before_action :set_project, only: [:show, :update, :destroy]

  def index
    @projects = @organization.projects.includes(:organization)
    track_feature_usage('projects_listed')
    render json: @projects.map { |p| project_with_stats(p) }
  end

  def show
    render json: project_with_stats(@project)
  end

  def create
    @project = @organization.projects.build(project_params)

    if @project.save
      log_audit('created_project', @project)
      track_feature_usage('projects_created')
      render json: project_with_stats(@project), status: :created
    else
      render json: { errors: @project.errors }, status: :unprocessable_entity
    end
  end

  def update
    if @project.update(project_params)
      log_audit('updated_project', @project)
      render json: project_with_stats(@project)
    else
      render json: { errors: @project.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    log_audit('deleted_project', @project)
    @project.destroy
    head :no_content
  end

  private

  def set_project
    @project = @organization.projects.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name, :description, :status)
  end

  def project_with_stats(project)
    project.as_json.merge(
      task_count: project.task_count,
      completed_task_count: project.completed_task_count,
      progress_percentage: project.progress_percentage
    )
  end
end