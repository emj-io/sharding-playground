class Api::V1::UsersController < Api::V1::BaseController
  before_action :ensure_organization
  before_action :set_user, only: [:show, :update, :destroy]

  def index
    @users = @organization.users.includes(:organization)
    track_feature_usage('users_listed')
    render json: @users
  end

  def show
    render json: @user
  end

  def create
    @user = @organization.users.build(user_params)

    if @user.save
      log_audit('created_user', @user)
      track_feature_usage('users_created')
      render json: @user, status: :created
    else
      render json: { errors: @user.errors }, status: :unprocessable_entity
    end
  end

  def update
    if @user.update(user_params)
      log_audit('updated_user', @user)
      render json: @user
    else
      render json: { errors: @user.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    log_audit('deleted_user', @user)
    @user.destroy
    head :no_content
  end

  private

  def set_user
    @user = @organization.users.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email, :name, :role)
  end
end