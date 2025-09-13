class Api::V1::TasksController < Api::V1::BaseController
  before_action :ensure_organization
  before_action :set_project, only: [:index, :create]
  before_action :set_task, only: [:show, :update, :destroy]

  def index
    if @project
      # Tasks for a specific project
      @tasks = @project.tasks.includes(:assigned_user, :project)
    else
      # All tasks for the organization
      @tasks = @organization.tasks.includes(:assigned_user, :project)
    end

    track_feature_usage('tasks_listed')
    render json: @tasks.map { |t| task_with_details(t) }
  end

  def show
    render json: task_with_details(@task)
  end

  def create
    @task = if @project
              @project.tasks.build(task_params)
            else
              @organization.tasks.build(task_params)
            end

    @task.organization = @organization

    if @task.save
      log_audit('created_task', @task)
      track_feature_usage('tasks_created')
      render json: task_with_details(@task), status: :created
    else
      render json: { errors: @task.errors }, status: :unprocessable_entity
    end
  end

  def update
    if @task.update(task_params)
      log_audit('updated_task', @task)
      render json: task_with_details(@task)
    else
      render json: { errors: @task.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    log_audit('deleted_task', @task)
    @task.destroy
    head :no_content
  end

  private

  def set_project
    return unless params[:project_id]

    @project = @organization.projects.find(params[:project_id])
  end

  def set_task
    @task = @organization.tasks.find(params[:id])
  end

  def task_params
    params.require(:task).permit(:title, :description, :status, :priority, :due_date, :assigned_user_id, :project_id)
  end

  def task_with_details(task)
    task.as_json(include: {
      project: { only: [:id, :name] },
      assigned_user: { only: [:id, :name, :email] }
    }).merge(
      overdue: task.overdue?,
      assigned: task.assigned?
    )
  end
end