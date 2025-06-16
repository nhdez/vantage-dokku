class DeploymentPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    user.present? && (record.user == user || user.admin?)
  end

  def create?
    user.present?
  end

  def new?
    create?
  end

  def update?
    user.present? && (record.user == user || user.admin?)
  end

  def edit?
    update?
  end

  def destroy?
    user.present? && (record.user == user || user.admin?)
  end

  def create_dokku_app?
    user.present? && (record.user == user || user.admin?)
  end

  def configure_domain?
    user.present? && (record.user == user || user.admin?)
  end

  def update_domains?
    user.present? && (record.user == user || user.admin?)
  end

  def attach_ssh_keys?
    user.present? && (record.user == user || user.admin?)
  end

  def update_ssh_keys?
    user.present? && (record.user == user || user.admin?)
  end

  def manage_environment?
    user.present? && (record.user == user || user.admin?)
  end

  def update_environment?
    user.present? && (record.user == user || user.admin?)
  end

  def configure_databases?
    user.present? && (record.user == user || user.admin?)
  end

  def update_database_configuration?
    user.present? && (record.user == user || user.admin?)
  end

  def delete_database_configuration?
    user.present? && (record.user == user || user.admin?)
  end

  def check_ssl_status?
    user.present? && (record.user == user || user.admin?)
  end

  def git_configuration?
    user.present? && (record.user == user || user.admin?)
  end

  def update_git_configuration?
    user.present? && (record.user == user || user.admin?)
  end

  def deploy?
    user.present? && (record.user == user || user.admin?)
  end

  def logs?
    user.present? && (record.user == user || user.admin?)
  end

  def execute_commands?
    user.present? && (record.user == user || user.admin?)
  end

  def run_command?
    user.present? && (record.user == user || user.admin?)
  end

  class Scope < Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.where(user: user)
      end
    end
  end
end