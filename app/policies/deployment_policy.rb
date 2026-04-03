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

  def delete_domain?
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

  def port_mappings?
    user.present? && (record.user == user || user.admin?)
  end

  def sync_port_mappings?
    user.present? && (record.user == user || user.admin?)
  end

  def add_port_mapping?
    user.present? && (record.user == user || user.admin?)
  end

  def remove_port_mapping?
    user.present? && (record.user == user || user.admin?)
  end

  def clear_port_mappings?
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

  def server_logs?
    user.present? && (record.user == user || user.admin?)
  end

  def start_log_streaming?
    user.present? && (record.user == user || user.admin?)
  end

  def stop_log_streaming?
    user.present? && (record.user == user || user.admin?)
  end

  def scans?
    user.present? && (record.user == user || user.admin?)
  end

  def trigger_scan?
    user.present? && (record.user == user || user.admin?)
  end

  def kamal_configuration?
    user.present? && (record.user == user || user.admin?)
  end

  def update_kamal_configuration?
    user.present? && (record.user == user || user.admin?)
  end

  def kamal_registry?
    user.present? && (record.user == user || user.admin?)
  end

  def update_kamal_registry?
    user.present? && (record.user == user || user.admin?)
  end

  def test_kamal_registry?
    user.present? && (record.user == user || user.admin?)
  end

  def provision_self_hosted_registry?
    user.present? && (record.user == user || user.admin?)
  end

  def kamal_accessories?
    user.present? && (record.user == user || user.admin?)
  end

  def add_kamal_accessory?
    user.present? && (record.user == user || user.admin?)
  end

  def remove_kamal_accessory?
    user.present? && (record.user == user || user.admin?)
  end

  def boot_kamal_accessory?
    user.present? && (record.user == user || user.admin?)
  end

  def reboot_kamal_accessory?
    user.present? && (record.user == user || user.admin?)
  end

  def kamal_setup?
    user.present? && (record.user == user || user.admin?)
  end

  def check_kamal_prerequisites?
    user.present? && (record.user == user || user.admin?)
  end

  def kamal_push_env?
    user.present? && (record.user == user || user.admin?)
  end

  def kamal_config_preview?
    user.present? && (record.user == user || user.admin?)
  end

  def download_kamal_config?
    user.present? && (record.user == user || user.admin?)
  end

  def kamal_rollback?
    user.present? && (record.user == user || user.admin?)
  end

  def kamal_restart?
    user.present? && (record.user == user || user.admin?)
  end

  def kamal_stop?
    user.present? && (record.user == user || user.admin?)
  end

  def kamal_start?
    user.present? && (record.user == user || user.admin?)
  end

  def kamal_proxy_reboot?
    user.present? && (record.user == user || user.admin?)
  end

  def kamal_app_details?
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
