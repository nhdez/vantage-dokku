class Admin::UsersController < ApplicationController
  include ActivityTrackable
  
  before_action :ensure_admin
  before_action :set_user, only: [:show, :edit, :update, :assign_role, :remove_role]
  
  def index
    # Simple search without Ransack for now
    users_scope = User.includes(:roles)
    
    if params[:q]
      if params[:q][:email_cont].present?
        users_scope = users_scope.where("email ILIKE ?", "%#{params[:q][:email_cont]}%")
      end
      if params[:q][:first_name_cont].present?
        users_scope = users_scope.where("first_name ILIKE ?", "%#{params[:q][:first_name_cont]}%")
      end
      if params[:q][:last_name_cont].present?
        users_scope = users_scope.where("last_name ILIKE ?", "%#{params[:q][:last_name_cont]}%")
      end
      if params[:q][:roles_name_eq].present?
        users_scope = users_scope.joins(:roles).where(roles: { name: params[:q][:roles_name_eq] })
      end
      if params[:q][:created_at_gteq].present?
        users_scope = users_scope.where("created_at >= ?", params[:q][:created_at_gteq])
      end
    end
    
    @pagy, @users = pagy(users_scope.order(created_at: :desc), items: 15)
    @roles = Role.all
    @q = params[:q] || {}
  end

  def show
    @user_roles = @user.roles
  end

  def edit
  end

  def update
    if @user.update(user_params)
      log_activity(ActivityLog::ACTIONS[:user_updated], 
                  details: "Updated user: #{@user.full_name}")
      toast_updated("User")
      redirect_to admin_user_path(@user)
    else
      toast_validation_errors(@user)
      render :edit
    end
  end

  def assign_role
    role = Role.find(params[:role_id])
    
    if @user.add_role(role.name)
      log_role_assignment(current_user, role.name, @user)
      toast_role_assigned(role.name, @user.full_name)
    else
      toast_error("Failed to assign role to #{@user.full_name}", title: "Role Assignment Failed")
    end
    
    redirect_to admin_user_path(@user)
  end

  def remove_role
    role = Role.find(params[:role_id])
    
    if @user.remove_role(role.name)
      log_role_removal(current_user, role.name, @user)
      toast_role_removed(role.name, @user.full_name)
    else
      toast_error("Failed to remove role from #{@user.full_name}", title: "Role Removal Failed")
    end
    
    redirect_to admin_user_path(@user)
  end

  private

  def ensure_admin
    redirect_to root_path, alert: "Access denied" unless current_user&.admin?
  end

  def set_user
    @user = User.find(params[:id])
  end

  def user_params
    params.require(:user).permit(:email, :first_name, :last_name, :date_of_birth, :profile_picture)
  end
end
