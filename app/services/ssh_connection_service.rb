require "net/ssh"
require "timeout"

# Facade that preserves the original public interface while delegating
# to focused sub-services under app/services/ssh/.
class SshConnectionService
  CONNECTION_TIMEOUT = Ssh::BaseService::CONNECTION_TIMEOUT
  COMMAND_TIMEOUT    = Ssh::BaseService::COMMAND_TIMEOUT
  UPDATE_TIMEOUT     = Ssh::BaseService::UPDATE_TIMEOUT
  INSTALL_TIMEOUT    = Ssh::BaseService::INSTALL_TIMEOUT
  DOMAIN_TIMEOUT     = Ssh::BaseService::DOMAIN_TIMEOUT
  ENV_TIMEOUT        = Ssh::BaseService::ENV_TIMEOUT

  def initialize(server)
    @server = server
  end

  # Server management
  def install_dokku_with_key_setup          = server_svc.install_dokku_with_key_setup
  def update_server_packages(&block)
    server_svc.update_server_packages(&block)
  end
  def restart_server                        = server_svc.restart_server
  def test_connection_and_gather_info       = server_svc.test_connection_and_gather_info

  # Dokku app management
  def create_dokku_app(app_name)            = app_svc.create_dokku_app(app_name)
  def destroy_dokku_app(app_name)           = app_svc.destroy_dokku_app(app_name)
  def list_dokku_apps                       = app_svc.list_dokku_apps
  def get_dokku_config(app_name)            = app_svc.get_dokku_config(app_name)
  def sync_dokku_ssh_keys(public_keys)      = app_svc.sync_dokku_ssh_keys(public_keys)
  def sync_dokku_environment_variables(app_name, env_vars) = app_svc.sync_dokku_environment_variables(app_name, env_vars)

  # Domain and SSL management
  def debug_dokku_domains(app_name)                        = domain_svc.debug_dokku_domains(app_name)
  def remove_domain_from_app(app_name, domain)             = domain_svc.remove_domain_from_app(app_name, domain)
  def sync_dokku_domains(app_name, domain_names)           = domain_svc.sync_dokku_domains(app_name, domain_names)

  # Database management
  def configure_database(app_name, database_config)        = db_svc.configure_database(app_name, database_config)
  def delete_database_configuration(app_name, db_config)   = db_svc.delete_database_configuration(app_name, db_config)

  # Port mappings
  def list_ports(app_name)                                  = port_svc.list_ports(app_name)
  def add_port(app_name, scheme, host_port, container_port) = port_svc.add_port(app_name, scheme, host_port, container_port)
  def remove_port(app_name, scheme, host_port, container_port) = port_svc.remove_port(app_name, scheme, host_port, container_port)
  def clear_ports(app_name)                                 = port_svc.clear_ports(app_name)

  # Firewall (UFW)
  def check_ufw_status                      = firewall_svc.check_ufw_status
  def configure_ufw_for_docker              = firewall_svc.configure_ufw_for_docker
  def enable_ufw                            = firewall_svc.enable_ufw
  def disable_ufw                           = firewall_svc.disable_ufw
  def list_ufw_rules                        = firewall_svc.list_ufw_rules
  def add_ufw_rule(rule_command)            = firewall_svc.add_ufw_rule(rule_command)
  def delete_ufw_rule(rule_number)          = firewall_svc.delete_ufw_rule(rule_number)
  def reset_ufw                             = firewall_svc.reset_ufw

  # Vulnerability scanning
  def check_go_version                      = vuln_svc.check_go_version
  def check_osv_scanner_version             = vuln_svc.check_osv_scanner_version
  def install_go(version, server_uuid)      = vuln_svc.install_go(version, server_uuid)
  def install_osv_scanner(server_uuid)      = vuln_svc.install_osv_scanner(server_uuid)
  def check_app_running(app_name)           = vuln_svc.check_app_running(app_name)
  def run_osv_scanner_on_container(app_name) = vuln_svc.run_osv_scanner_on_container(app_name)
  def perform_vulnerability_scan(deployment, scan_type = "manual") = vuln_svc.perform_vulnerability_scan(deployment, scan_type)

  private

  def server_svc   = @server_svc   ||= Ssh::ServerService.new(@server)
  def app_svc      = @app_svc      ||= Ssh::AppService.new(@server)
  def domain_svc   = @domain_svc   ||= Ssh::DomainService.new(@server)
  def db_svc       = @db_svc       ||= Ssh::DatabaseService.new(@server)
  def port_svc     = @port_svc     ||= Ssh::PortService.new(@server)
  def firewall_svc = @firewall_svc ||= Ssh::FirewallService.new(@server)
  def vuln_svc     = @vuln_svc     ||= Ssh::VulnerabilityService.new(@server)
end
