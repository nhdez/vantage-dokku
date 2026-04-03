class ServerPolicy < ApplicationPolicy
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

  def test_connection?
    user.present? && (record.user == user || user.admin?)
  end

  def update_server?
    user.present? && (record.user == user || user.admin?)
  end

  def install_dokku?
    user.present? && (record.user == user || user.admin?)
  end

  def restart_server?
    user.present? && (record.user == user || user.admin?)
  end

  def logs?
    user.present? && (record.user == user || user.admin?)
  end

  def firewall_rules?
    user.present? && (record.user == user || user.admin?)
  end

  def sync_firewall_rules?
    user.present? && (record.user == user || user.admin?)
  end

  def enable_ufw?
    user.present? && (record.user == user || user.admin?)
  end

  def disable_ufw?
    user.present? && (record.user == user || user.admin?)
  end

  def add_firewall_rule?
    user.present? && (record.user == user || user.admin?)
  end

  def remove_firewall_rule?
    user.present? && (record.user == user || user.admin?)
  end

  def toggle_firewall_rule?
    user.present? && (record.user == user || user.admin?)
  end

  def apply_firewall_rules?
    user.present? && (record.user == user || user.admin?)
  end

  def vulnerability_scanner?
    user.present? && (record.user == user || user.admin?)
  end

  def check_scanner_status?
    user.present? && (record.user == user || user.admin?)
  end

  def install_go?
    user.present? && (record.user == user || user.admin?)
  end

  def install_osv_scanner?
    user.present? && (record.user == user || user.admin?)
  end

  def update_scan_config?
    user.present? && (record.user == user || user.admin?)
  end

  def scan_all_deployments?
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
