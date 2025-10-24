require 'net/ssh'
require 'timeout'

class SshConnectionService
  CONNECTION_TIMEOUT = 10 # seconds
  COMMAND_TIMEOUT = 30 # seconds
  UPDATE_TIMEOUT = 600 # seconds (10 minutes for server updates)
  INSTALL_TIMEOUT = 900 # seconds (15 minutes for Dokku installation)
  DOMAIN_TIMEOUT = 600 # seconds (10 minutes for domain and SSL configuration)
  ENV_TIMEOUT = 180 # seconds (3 minutes for environment variable operations)
  
  def initialize(server)
    @server = server
    @connection_details = server.connection_details
  end
  
  def install_dokku_with_key_setup
    result = {
      success: false,
      error: nil,
      output: '',
      dokku_installed: false
    }
    
    begin
      Timeout::timeout(INSTALL_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Setup SSH key and install Dokku
          result[:output] = perform_dokku_installation(ssh)
          result[:success] = true
          result[:dokku_installed] = true
          
          # Update server info after installation
          gather_server_info_after_install(ssh)
          
          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      result[:error] = "Authentication failed. Please check your SSH key or password."
    rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
      result[:error] = "Connection timeout. Server may be unreachable."
    rescue Errno::ECONNREFUSED => e
      result[:error] = "Connection refused. Check if SSH service is running on port #{@connection_details[:port]}."
    rescue Errno::EHOSTUNREACH => e
      result[:error] = "Host unreachable. Check the IP address and network connectivity."
    rescue StandardError => e
      result[:error] = "Dokku installation failed: #{e.message}"
    end
    
    result
  end

  def update_server_packages
    result = {
      success: false,
      error: nil,
      output: '',
      packages_updated: 0
    }
    
    begin
      Timeout::timeout(UPDATE_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Run system update commands
          result[:output] = perform_system_update(ssh)
          result[:success] = true
          
          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      result[:error] = "Authentication failed. Please check your SSH key or password."
    rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
      result[:error] = "Connection timeout. Server may be unreachable."
    rescue Errno::ECONNREFUSED => e
      result[:error] = "Connection refused. Check if SSH service is running on port #{@connection_details[:port]}."
    rescue Errno::EHOSTUNREACH => e
      result[:error] = "Host unreachable. Check the IP address and network connectivity."
    rescue StandardError => e
      result[:error] = "Update failed: #{e.message}"
    end
    
    result
  end

  def restart_server
    result = {
      success: false,
      error: nil,
      output: ''
    }
    
    begin
      Timeout::timeout(CONNECTION_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Execute restart command
          result[:output] = perform_server_restart(ssh)
          result[:success] = true
          
          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      result[:error] = "Authentication failed. Please check your SSH key or password."
    rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
      result[:error] = "Connection timeout. Server may be unreachable."
    rescue Errno::ECONNREFUSED => e
      result[:error] = "Connection refused. Check if SSH service is running on port #{@connection_details[:port]}."
    rescue Errno::EHOSTUNREACH => e
      result[:error] = "Host unreachable. Check the IP address and network connectivity."
    rescue StandardError => e
      result[:error] = "Restart failed: #{e.message}"
    end
    
    result
  end

  def debug_dokku_domains(app_name)
    result = {
      success: false,
      error: nil,
      output: ''
    }

    begin
      Timeout::timeout(COMMAND_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          debug_output = "=== Dokku Domain Debug for #{app_name} ===\n\n"

          # Check if app exists
          app_check = execute_command(ssh, "sudo dokku apps:list | grep #{app_name} || echo 'NOT_FOUND'")
          debug_output += "App exists: #{!app_check&.include?('NOT_FOUND')}\n\n"

          # Get domain configuration
          debug_output += "=== Domain Configuration ===\n"
          domains = execute_command(ssh, "sudo dokku domains:report #{app_name} 2>&1")
          debug_output += domains if domains
          debug_output += "\n"

          # Check nginx configuration
          debug_output += "=== Nginx Configuration ===\n"
          nginx_conf = execute_command(ssh, "sudo cat /home/dokku/#{app_name}/nginx.conf 2>&1 | head -50")
          debug_output += nginx_conf if nginx_conf
          debug_output += "\n"

          # Check SSL status
          debug_output += "=== Let's Encrypt Status ===\n"
          ssl_status = execute_command(ssh, "sudo dokku letsencrypt:list | grep #{app_name} || echo 'NO_SSL'")
          debug_output += ssl_status if ssl_status
          debug_output += "\n"

          # Check certificate details
          debug_output += "=== Certificate Details ===\n"
          cert_info = execute_command(ssh, "sudo dokku letsencrypt:info #{app_name} 2>&1")
          debug_output += cert_info if cert_info
          debug_output += "\n"

          # Check proxy ports
          debug_output += "=== Proxy Ports ===\n"
          ports = execute_command(ssh, "sudo dokku proxy:ports #{app_name} 2>&1")
          debug_output += ports if ports
          debug_output += "\n"

          # List all apps and their domains for comparison
          debug_output += "=== All Apps on Server ===\n"
          all_apps = execute_command(ssh, "sudo dokku apps:list 2>&1")
          debug_output += all_apps if all_apps
          debug_output += "\n"

          # Check for domain conflicts
          debug_output += "=== Checking Domain Conflicts ===\n"
          all_domains = execute_command(ssh, "for app in $(sudo dokku apps:list 2>/dev/null | grep -v '====' | grep .); do echo \"App: $app\"; sudo dokku domains:report $app --domains-app-vhosts 2>/dev/null; echo '---'; done")
          debug_output += all_domains if all_domains

          result[:output] = debug_output
          result[:success] = true
        end
      end
    rescue StandardError => e
      result[:error] = "Debug failed: #{e.message}"
    end

    result
  end

  def destroy_dokku_app(app_name)
    result = {
      success: false,
      error: nil,
      output: ''
    }

    begin
      Timeout::timeout(COMMAND_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          Rails.logger.info "Destroying Dokku app '#{app_name}' on #{@server.name}"

          # Check if app exists first
          check_app = execute_command(ssh, "sudo dokku apps:exists #{app_name} 2>&1")

          if check_app.nil? || check_app.include?("does not exist")
            Rails.logger.info "Dokku app '#{app_name}' does not exist on server, skipping destruction"
            result[:success] = true
            result[:output] = "App does not exist on server (already deleted or never created)"
          else
            # Destroy the app with --force to skip confirmation
            destroy_output = execute_command(ssh, "sudo dokku apps:destroy #{app_name} --force 2>&1")

            if destroy_output
              result[:output] = destroy_output
              result[:success] = !destroy_output.include?("ERROR") && !destroy_output.include?("failed")

              if result[:success]
                Rails.logger.info "Successfully destroyed Dokku app '#{app_name}' on #{@server.name}"
              else
                result[:error] = "Failed to destroy app: #{destroy_output}"
                Rails.logger.error result[:error]
              end
            else
              result[:error] = "No response from destroy command"
            end
          end

          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      result[:error] = "Authentication failed. Please check your SSH key or password."
    rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
      result[:error] = "Connection timeout. Server may be unreachable."
    rescue Errno::ECONNREFUSED => e
      result[:error] = "Connection refused. Check if SSH service is running on port #{@connection_details[:port]}."
    rescue Errno::EHOSTUNREACH => e
      result[:error] = "Host unreachable. Check the IP address and network connectivity."
    rescue StandardError => e
      result[:error] = "Failed to destroy app: #{e.message}"
    end

    result
  end

  def create_dokku_app(app_name)
    result = {
      success: false,
      error: nil,
      output: ''
    }
    
    begin
      Timeout::timeout(CONNECTION_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Create Dokku app
          result[:output] = perform_dokku_app_creation(ssh, app_name)
          result[:success] = true
          
          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      result[:error] = "Authentication failed. Please check your SSH key or password."
    rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
      result[:error] = "Connection timeout. Server may be unreachable."
    rescue Errno::ECONNREFUSED => e
      result[:error] = "Connection refused. Check if SSH service is running on port #{@connection_details[:port]}."
    rescue Errno::EHOSTUNREACH => e
      result[:error] = "Host unreachable. Check the IP address and network connectivity."
    rescue StandardError => e
      result[:error] = "Dokku app creation failed: #{e.message}"
    end
    
    result
  end

  def sync_dokku_ssh_keys(public_keys)
    result = {
      success: false,
      error: nil,
      output: ''
    }
    
    begin
      Timeout::timeout(CONNECTION_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Sync SSH keys to Dokku
          result[:output] = perform_dokku_ssh_key_sync(ssh, public_keys)
          result[:success] = true
          
          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      result[:error] = "Authentication failed. Please check your SSH key or password."
    rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
      result[:error] = "Connection timeout. Server may be unreachable."
    rescue Errno::ECONNREFUSED => e
      result[:error] = "Connection refused. Check if SSH service is running on port #{@connection_details[:port]}."
    rescue Errno::EHOSTUNREACH => e
      result[:error] = "Host unreachable. Check the IP address and network connectivity."
    rescue StandardError => e
      result[:error] = "SSH key sync failed: #{e.message}"
    end
    
    result
  end

  def sync_dokku_environment_variables(app_name, env_vars)
    result = {
      success: false,
      error: nil,
      output: ''
    }
    
    begin
      Timeout::timeout(ENV_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Sync environment variables to Dokku app
          result[:output] = perform_dokku_env_sync(ssh, app_name, env_vars)
          result[:success] = true
          
          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      result[:error] = "Authentication failed. Please check your SSH key or password."
    rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
      result[:error] = "Operation timeout. Environment variable sync may take longer with many variables."
    rescue Errno::ECONNREFUSED => e
      result[:error] = "Connection refused. Check if SSH service is running on port #{@connection_details[:port]}."
    rescue Errno::EHOSTUNREACH => e
      result[:error] = "Host unreachable. Check the IP address and network connectivity."
    rescue StandardError => e
      result[:error] = "Environment variables sync failed: #{e.message}"
    end
    
    result
  end

  def remove_domain_from_app(app_name, domain_to_remove)
    result = {
      success: false,
      error: nil,
      output: ''
    }

    begin
      Timeout::timeout(DOMAIN_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          removal_output = "=== Removing Domain #{domain_to_remove} from App #{app_name} ===\n\n"

          # Check if app exists
          app_check = execute_command(ssh, "sudo dokku apps:list | grep '^#{app_name}$' || echo 'APP_NOT_FOUND'")
          if app_check&.include?('APP_NOT_FOUND')
            removal_output += "App '#{app_name}' does not exist.\n"
            result[:success] = true  # Consider it success if app doesn't exist
            result[:output] = removal_output
            return result
          end

          # Get current domains
          removal_output += "Getting current domains...\n"
          current_domains_cmd = "sudo dokku domains:report #{app_name} --domains-app-vhosts 2>/dev/null"
          current_domains_result = execute_command(ssh, current_domains_cmd)

          if current_domains_result
            current_domains = current_domains_result.split.reject { |d| d.empty? }
            removal_output += "Current domains: #{current_domains.join(', ')}\n"

            # Remove the specified domain
            remaining_domains = current_domains - [domain_to_remove]

            if remaining_domains.empty?
              # If no domains left, clear all domains and disable SSL
              removal_output += "\n=== No domains remaining, clearing all domains and SSL ===\n"

              # Disable SSL first
              removal_output += "Disabling SSL...\n"
              disable_ssl = execute_command(ssh, "sudo dokku letsencrypt:disable #{app_name} 2>&1")
              removal_output += disable_ssl if disable_ssl

              # Clear all domains
              removal_output += "Clearing all domains...\n"
              clear_cmd = "sudo dokku domains:clear #{app_name} 2>&1"
              clear_result = execute_command(ssh, clear_cmd)
              removal_output += clear_result if clear_result

              removal_output += "\nApp will now use default Dokku domain.\n"
            else
              # Update domains to remaining ones
              removal_output += "\n=== Updating domains to remove #{domain_to_remove} ===\n"

              # First disable SSL to avoid certificate conflicts
              removal_output += "Temporarily disabling SSL...\n"
              disable_ssl = execute_command(ssh, "sudo dokku letsencrypt:disable #{app_name} 2>&1")

              # Set the new domain list
              domains_string = remaining_domains.join(' ')
              set_cmd = "sudo dokku domains:set #{app_name} #{domains_string} 2>&1"
              removal_output += "Setting domains to: #{domains_string}\n"
              set_result = execute_command(ssh, set_cmd)
              removal_output += set_result if set_result

              # Re-enable SSL for remaining domains (if app is deployed)
              ps_check = execute_command(ssh, "sudo dokku ps:report #{app_name} --ps-running 2>&1")
              if ps_check && ps_check.include?("true")
                removal_output += "\n=== Re-enabling SSL for remaining domains ===\n"

                # Clear any app-specific server setting that might be wrong
                clear_server = "sudo dokku letsencrypt:set #{app_name} server 2>&1"
                execute_command(ssh, clear_server)

                # Enable SSL
                ssl_cmd = "sudo dokku letsencrypt:enable #{app_name} 2>&1"
                ssl_result = execute_long_command(ssh, ssl_cmd, 300)
                removal_output += ssl_result if ssl_result

                if ssl_result && (ssl_result.include?("Certificate retrieved successfully") || ssl_result.include?("done"))
                  removal_output += "\n✅ SSL re-enabled for remaining domains.\n"
                else
                  removal_output += "\n⚠️ SSL may need manual configuration.\n"
                end
              else
                removal_output += "\n⚠️ App not running, skipping SSL reconfiguration.\n"
              end
            end

            removal_output += "\n✅ Domain #{domain_to_remove} removed successfully!\n"
          else
            removal_output += "Could not retrieve current domains.\n"
          end

          result[:output] = removal_output
          result[:success] = true

          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Domain removal failed: #{e.message}"
      Rails.logger.error result[:error]
    end

    result
  end

  def sync_dokku_domains(app_name, domain_names)
    result = {
      success: false,
      error: nil,
      output: ''
    }
    
    begin
      Timeout::timeout(DOMAIN_TIMEOUT) do # Allow sufficient time for domain and SSL operations
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Sync domains to Dokku app and configure SSL
          result[:output] = perform_dokku_domain_sync(ssh, app_name, domain_names)
          result[:success] = true
          
          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      result[:error] = "Authentication failed. Please check your SSH key or password."
    rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
      result[:error] = "Connection timeout. Server may be unreachable."
    rescue Errno::ECONNREFUSED => e
      result[:error] = "Connection refused. Check if SSH service is running on port #{@connection_details[:port]}."
    rescue Errno::EHOSTUNREACH => e
      result[:error] = "Host unreachable. Check the IP address and network connectivity."
    rescue StandardError => e
      result[:error] = "Domain sync failed: #{e.message}"
    end
    
    result
  end

  def configure_database(app_name, database_config)
    result = {
      success: false,
      error: nil,
      output: '',
      database_url: nil,
      redis_url: nil
    }

    begin
      Timeout::timeout(INSTALL_TIMEOUT) do # Use install timeout for database setup
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Configure database and optionally Redis
          config_result = perform_database_configuration(ssh, app_name, database_config)
          result[:output] = config_result[:output]
          result[:database_url] = config_result[:database_url]
          result[:redis_url] = config_result[:redis_url]
          result[:success] = true

          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      result[:error] = "Authentication failed. Please check your SSH key or password."
    rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
      result[:error] = "Connection timeout. Database configuration may take several minutes."
    rescue Errno::ECONNREFUSED => e
      result[:error] = "Connection refused. Check if SSH service is running on port #{@connection_details[:port]}."
    rescue Errno::EHOSTUNREACH => e
      result[:error] = "Host unreachable. Check the IP address and network connectivity."
    rescue StandardError => e
      result[:error] = "Database configuration failed: #{e.message}"
    end

    result
  end

  def delete_database_configuration(app_name, database_config)
    result = {
      success: false,
      error: nil,
      output: ''
    }
    
    begin
      Timeout::timeout(ENV_TIMEOUT) do # Use environment timeout for database operations
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Delete database configuration
          result[:output] = perform_database_deletion(ssh, app_name, database_config)
          result[:success] = true
          
          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      result[:error] = "Authentication failed. Please check your SSH key or password."
    rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
      result[:error] = "Operation timeout. Database deletion may take several minutes."
    rescue Errno::ECONNREFUSED => e
      result[:error] = "Connection refused. Check if SSH service is running on port #{@connection_details[:port]}."
    rescue Errno::EHOSTUNREACH => e
      result[:error] = "Host unreachable. Check the IP address and network connectivity."
    rescue StandardError => e
      result[:error] = "Database deletion failed: #{e.message}"
    end
    
    result
  end

  def test_connection_and_gather_info
    result = {
      success: false,
      error: nil,
      server_info: {}
    }

    begin
      Timeout::timeout(CONNECTION_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          result[:success] = true
          result[:server_info] = gather_server_info(ssh)

          # Update server with gathered information
          update_server_info(result[:server_info])
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      result[:error] = "Authentication failed. Please check your SSH key or password."
    rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
      result[:error] = "Connection timeout. Server may be unreachable."
    rescue Errno::ECONNREFUSED => e
      result[:error] = "Connection refused. Check if SSH service is running on port #{@connection_details[:port]}."
    rescue Errno::EHOSTUNREACH => e
      result[:error] = "Host unreachable. Check the IP address and network connectivity."
    rescue StandardError => e
      result[:error] = "Connection failed: #{e.message}"
    end

    # Update connection status
    if result[:success]
      @server.update!(
        connection_status: 'connected',
        last_connected_at: Time.current
      )
    else
      @server.update!(connection_status: 'failed')
    end

    result
  end

  def get_dokku_config(app_name)
    result = {
      success: false,
      error: nil,
      config: {}
    }

    begin
      Rails.logger.info "[SshConnectionService] Getting Dokku config for app #{app_name} on #{@server.name}"

      Timeout::timeout(CONNECTION_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Get config from Dokku (without --export flag, which doesn't exist in older versions)
          config_output = execute_command(ssh, "sudo dokku config:show #{app_name} 2>&1")

          if config_output && !config_output.include?('does not exist')
            # Parse the output to extract key-value pairs
            # Format: KEY:  value (with spaces after the colon)
            config_output.each_line do |line|
              # Skip header line (=====> app_name env vars)
              next if line.include?('====>')

              # Match format: KEY:  value
              # The regex handles variable amounts of whitespace after the colon
              match = line.match(/^([A-Z_][A-Z0-9_]*):\s+(.+)$/i)
              if match
                key = match[1].strip
                value = match[2].strip
                result[:config][key] = value
              end
            end

            Rails.logger.info "[SshConnectionService] Parsed #{result[:config].keys.count} environment variables from Dokku config"
            result[:success] = true
          else
            result[:error] = "App does not exist or no config found"
            Rails.logger.warn "[SshConnectionService] #{result[:error]}: #{config_output&.first(200)}"
          end

          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      result[:error] = "Authentication failed. Please check your SSH key or password."
      Rails.logger.error "[SshConnectionService] #{result[:error]}: #{e.message}"
    rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
      result[:error] = "Connection timeout. Server may be unreachable."
      Rails.logger.error "[SshConnectionService] #{result[:error]}: #{e.message}"
    rescue Errno::ECONNREFUSED => e
      result[:error] = "Connection refused. Check if SSH service is running on port #{@connection_details[:port]}."
      Rails.logger.error "[SshConnectionService] #{result[:error]}: #{e.message}"
    rescue Errno::EHOSTUNREACH => e
      result[:error] = "Host unreachable. Check the IP address and network connectivity."
      Rails.logger.error "[SshConnectionService] #{result[:error]}: #{e.message}"
    rescue StandardError => e
      result[:error] = "Failed to get config: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
      Rails.logger.error e.backtrace.join("\n")
    end

    result
  end

  # List port mappings for an app
  def list_ports(app_name)
    result = {
      success: false,
      error: nil,
      ports: []
    }

    begin
      Rails.logger.info "[SshConnectionService] Listing port mappings for app #{app_name} on #{@server.name}"

      Timeout::timeout(CONNECTION_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Get port mappings from Dokku
          ports_output = execute_command(ssh, "sudo dokku ports:list #{app_name} 2>&1")

          if ports_output && !ports_output.include?('does not exist') && !ports_output.include?('No port mappings')
            # Parse the output to extract port mappings
            # Format: -----> scheme  host port  container port
            ports_output.each_line do |line|
              # Skip header and separator lines
              next if line.include?('------>') || line.strip.empty?

              # Match format: scheme  host_port  container_port (with variable whitespace)
              match = line.match(/^\s*(\w+)\s+(\d+)\s+(\d+)\s*$/)
              if match
                result[:ports] << {
                  scheme: match[1],
                  host_port: match[2].to_i,
                  container_port: match[3].to_i
                }
              end
            end

            Rails.logger.info "[SshConnectionService] Found #{result[:ports].count} port mappings"
            result[:success] = true
          elsif ports_output&.include?('No port mappings')
            # No ports configured, but that's not an error
            Rails.logger.info "[SshConnectionService] No port mappings configured for #{app_name}"
            result[:success] = true
          else
            result[:error] = "App does not exist or error retrieving ports"
            Rails.logger.warn "[SshConnectionService] #{result[:error]}: #{ports_output&.first(200)}"
          end

          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue Net::SSH::AuthenticationFailed => e
      result[:error] = "Authentication failed. Please check your SSH key or password."
      Rails.logger.error "[SshConnectionService] #{result[:error]}: #{e.message}"
    rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
      result[:error] = "Connection timeout. Server may be unreachable."
      Rails.logger.error "[SshConnectionService] #{result[:error]}: #{e.message}"
    rescue Errno::ECONNREFUSED => e
      result[:error] = "Connection refused. Check if SSH service is running on port #{@connection_details[:port]}."
      Rails.logger.error "[SshConnectionService] #{result[:error]}: #{e.message}"
    rescue Errno::EHOSTUNREACH => e
      result[:error] = "Host unreachable. Check the IP address and network connectivity."
      Rails.logger.error "[SshConnectionService] #{result[:error]}: #{e.message}"
    rescue StandardError => e
      result[:error] = "Failed to list ports: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
      Rails.logger.error e.backtrace.join("\n")
    end

    result
  end

  # Add port mapping to an app
  def add_port(app_name, scheme, host_port, container_port)
    result = {
      success: false,
      error: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Adding port mapping #{scheme}:#{host_port}:#{container_port} to app #{app_name}"

      Timeout::timeout(CONNECTION_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Add port mapping
          port_string = "#{scheme}:#{host_port}:#{container_port}"
          output = execute_command(ssh, "sudo dokku ports:add #{app_name} #{port_string} 2>&1")

          if output && !output.include?('does not exist') && !output.downcase.include?('error')
            Rails.logger.info "[SshConnectionService] Successfully added port mapping"
            result[:success] = true
          else
            result[:error] = output || "Failed to add port mapping"
            Rails.logger.error "[SshConnectionService] #{result[:error]}"
          end

          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to add port mapping: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
      Rails.logger.error e.backtrace.join("\n")
    end

    result
  end

  # Remove port mapping from an app
  def remove_port(app_name, scheme, host_port, container_port)
    result = {
      success: false,
      error: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Removing port mapping #{scheme}:#{host_port}:#{container_port} from app #{app_name}"

      Timeout::timeout(CONNECTION_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Remove port mapping
          port_string = "#{scheme}:#{host_port}:#{container_port}"
          output = execute_command(ssh, "sudo dokku ports:remove #{app_name} #{port_string} 2>&1")

          if output && !output.include?('does not exist') && !output.downcase.include?('error')
            Rails.logger.info "[SshConnectionService] Successfully removed port mapping"
            result[:success] = true
          else
            result[:error] = output || "Failed to remove port mapping"
            Rails.logger.error "[SshConnectionService] #{result[:error]}"
          end

          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to remove port mapping: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
      Rails.logger.error e.backtrace.join("\n")
    end

    result
  end

  # Clear all port mappings for an app
  def clear_ports(app_name)
    result = {
      success: false,
      error: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Clearing all port mappings for app #{app_name}"

      Timeout::timeout(CONNECTION_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Clear all port mappings
          output = execute_command(ssh, "sudo dokku ports:clear #{app_name} 2>&1")

          if output && !output.include?('does not exist') && !output.downcase.include?('error')
            Rails.logger.info "[SshConnectionService] Successfully cleared all port mappings"
            result[:success] = true
          else
            result[:error] = output || "Failed to clear port mappings"
            Rails.logger.error "[SshConnectionService] #{result[:error]}"
          end

          # Update last connected timestamp
          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to clear port mappings: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
      Rails.logger.error e.backtrace.join("\n")
    end

    result
  end

  # Check UFW status
  def check_ufw_status
    result = {
      success: false,
      error: nil,
      enabled: false,
      status: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Checking UFW status on #{@server.name}"

      Timeout::timeout(COMMAND_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          status_output = execute_command(ssh, "sudo ufw status 2>&1")

          if status_output
            result[:status] = status_output
            result[:enabled] = status_output.include?('Status: active')
            result[:success] = true
            Rails.logger.info "[SshConnectionService] UFW status: #{result[:enabled] ? 'enabled' : 'disabled'}"
          else
            result[:error] = "Failed to get UFW status"
          end

          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to check UFW status: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
      Rails.logger.error e.backtrace.join("\n")
    end

    result
  end

  # Configure UFW to work with Docker/Dokku
  def configure_ufw_for_docker
    result = {
      success: false,
      error: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Configuring UFW for Docker compatibility on #{@server.name}"

      Timeout::timeout(COMMAND_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Check if Docker configuration already exists
          check_output = execute_command(ssh, "sudo grep -q 'DOCKER-USER' /etc/ufw/after.rules && echo 'exists' || echo 'not_exists'")

          if check_output&.strip == 'not_exists'
            Rails.logger.info "[SshConnectionService] Adding Docker compatibility rules to UFW"

            # Backup the original file
            execute_command(ssh, "sudo cp /etc/ufw/after.rules /etc/ufw/after.rules.bak")

            # Use awk to insert the DOCKER-USER rules before the first COMMIT in the *filter section
            # This properly adds the chain definitions and rules within the existing *filter table
            configure_cmd = <<~'CMD'.strip
              sudo awk '
              BEGIN { in_filter=0; added=0 }
              /^\*filter/ { in_filter=1; print; next }
              /^COMMIT/ && in_filter && !added {
                print ""
                print "# BEGIN UFW AND DOCKER"
                print ":DOCKER-USER - [0:0]"
                print ":ufw-user-input - [0:0]"
                print ""
                print "-A DOCKER-USER -j ufw-user-input"
                print "-A DOCKER-USER -j RETURN"
                print "# END UFW AND DOCKER"
                print ""
                added=1
              }
              { print }
              ' /etc/ufw/after.rules > /tmp/after.rules.tmp && sudo mv /tmp/after.rules.tmp /etc/ufw/after.rules
            CMD

            # Execute the command
            output = execute_command(ssh, configure_cmd)

            Rails.logger.info "[SshConnectionService] Docker compatibility rules added to UFW"
            result[:success] = true
          else
            Rails.logger.info "[SshConnectionService] Docker compatibility rules already exist in UFW"
            result[:success] = true
          end

          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to configure UFW for Docker: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
      Rails.logger.error e.backtrace.join("\n")
    end

    result
  end

  # Enable UFW (with automatic Docker configuration and essential rules)
  def enable_ufw
    result = {
      success: false,
      error: nil,
      warnings: []
    }

    begin
      Rails.logger.info "[SshConnectionService] Enabling UFW on #{@server.name}"

      Timeout::timeout(COMMAND_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Step 1: Configure UFW for Docker compatibility
          Rails.logger.info "[SshConnectionService] Step 1: Configuring UFW for Docker"
          docker_config_result = configure_ufw_for_docker
          unless docker_config_result[:success]
            result[:warnings] << "Failed to configure Docker compatibility: #{docker_config_result[:error]}"
          end

          # Step 2: Add essential rules (SSH, HTTP, HTTPS) before enabling
          Rails.logger.info "[SshConnectionService] Step 2: Adding essential rules"

          # Allow SSH (critical to prevent lockout)
          execute_command(ssh, "sudo ufw allow 22/tcp comment 'SSH' 2>&1")

          # Allow HTTP and HTTPS for Dokku apps
          execute_command(ssh, "sudo ufw allow 80/tcp comment 'HTTP' 2>&1")
          execute_command(ssh, "sudo ufw allow 443/tcp comment 'HTTPS' 2>&1")

          # Step 3: Enable UFW (--force to skip confirmation)
          Rails.logger.info "[SshConnectionService] Step 3: Enabling UFW"
          output = execute_command(ssh, "sudo ufw --force enable 2>&1")

          if output && !output.downcase.include?('error')
            # Step 4: Restart Docker to ensure compatibility
            Rails.logger.info "[SshConnectionService] Step 4: Restarting Docker"
            restart_output = execute_command(ssh, "sudo systemctl restart docker 2>&1")

            if restart_output && restart_output.downcase.include?('error')
              result[:warnings] << "Docker restart may have failed: #{restart_output}"
            end

            Rails.logger.info "[SshConnectionService] UFW enabled successfully with Docker compatibility"
            result[:success] = true
          else
            result[:error] = output || "Failed to enable UFW"
            Rails.logger.error "[SshConnectionService] #{result[:error]}"
          end

          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to enable UFW: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
      Rails.logger.error e.backtrace.join("\n")
    end

    result
  end

  # Disable UFW
  def disable_ufw
    result = {
      success: false,
      error: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Disabling UFW on #{@server.name}"

      Timeout::timeout(COMMAND_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          output = execute_command(ssh, "sudo ufw disable 2>&1")

          if output && !output.downcase.include?('error')
            Rails.logger.info "[SshConnectionService] UFW disabled successfully"
            result[:success] = true
          else
            result[:error] = output || "Failed to disable UFW"
            Rails.logger.error "[SshConnectionService] #{result[:error]}"
          end

          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to disable UFW: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
      Rails.logger.error e.backtrace.join("\n")
    end

    result
  end

  # List UFW rules
  def list_ufw_rules
    result = {
      success: false,
      error: nil,
      rules: []
    }

    begin
      Rails.logger.info "[SshConnectionService] Listing UFW rules on #{@server.name}"

      Timeout::timeout(COMMAND_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          output = execute_command(ssh, "sudo ufw status numbered 2>&1")

          if output && !output.downcase.include?('error')
            # Parse UFW rules from numbered output
            output.each_line do |line|
              # Match format: [ 1] 22/tcp ALLOW IN Anywhere
              match = line.match(/\[\s*(\d+)\]\s+(.+?)\s+(ALLOW|DENY|LIMIT|REJECT)\s+(IN|OUT)\s+(.+?)(\s+\((.+?)\))?$/)
              if match
                result[:rules] << {
                  number: match[1].to_i,
                  port_proto: match[2].strip,
                  action: match[3].downcase,
                  direction: match[4].downcase,
                  from: match[5].strip,
                  comment: match[7]
                }
              end
            end

            Rails.logger.info "[SshConnectionService] Found #{result[:rules].count} UFW rules"
            result[:success] = true
          else
            result[:error] = "Failed to list UFW rules"
          end

          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to list UFW rules: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
      Rails.logger.error e.backtrace.join("\n")
    end

    result
  end

  # Add UFW rule
  def add_ufw_rule(rule_command)
    result = {
      success: false,
      error: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Adding UFW rule on #{@server.name}: #{rule_command}"

      Timeout::timeout(COMMAND_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          output = execute_command(ssh, "sudo #{rule_command} 2>&1")

          if output && !output.downcase.include?('error') && !output.downcase.include?('could not')
            Rails.logger.info "[SshConnectionService] UFW rule added successfully"
            result[:success] = true
          else
            result[:error] = output || "Failed to add UFW rule"
            Rails.logger.error "[SshConnectionService] #{result[:error]}"
          end

          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to add UFW rule: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
      Rails.logger.error e.backtrace.join("\n")
    end

    result
  end

  # Delete UFW rule by number
  def delete_ufw_rule(rule_number)
    result = {
      success: false,
      error: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Deleting UFW rule ##{rule_number} on #{@server.name}"

      Timeout::timeout(COMMAND_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Use --force to skip confirmation
          output = execute_command(ssh, "yes | sudo ufw delete #{rule_number} 2>&1")

          if output && !output.downcase.include?('error')
            Rails.logger.info "[SshConnectionService] UFW rule deleted successfully"
            result[:success] = true
          else
            result[:error] = output || "Failed to delete UFW rule"
            Rails.logger.error "[SshConnectionService] #{result[:error]}"
          end

          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to delete UFW rule: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
      Rails.logger.error e.backtrace.join("\n")
    end

    result
  end

  # Reset UFW (clear all rules)
  def reset_ufw
    result = {
      success: false,
      error: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Resetting UFW on #{@server.name}"

      Timeout::timeout(COMMAND_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Use --force to skip confirmation
          output = execute_command(ssh, "yes | sudo ufw --force reset 2>&1")

          if output && !output.downcase.include?('error')
            Rails.logger.info "[SshConnectionService] UFW reset successfully"
            result[:success] = true
          else
            result[:error] = output || "Failed to reset UFW"
            Rails.logger.error "[SshConnectionService] #{result[:error]}"
          end

          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to reset UFW: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
      Rails.logger.error e.backtrace.join("\n")
    end

    result
  end

  # Check if Go is installed and return version
  def check_go_version
    result = {
      success: false,
      installed: false,
      version: nil,
      error: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Checking Go version on #{@server.name}"

      Timeout::timeout(CONNECTION_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          output = execute_command(ssh, "/usr/local/go/bin/go version 2>&1")

          if output && !output.downcase.include?('not found') && !output.downcase.include?('no such file')
            # Parse version from output like "go version go1.23.5 linux/amd64"
            if match = output.match(/go version (go[\d.]+)/)
              result[:installed] = true
              result[:version] = match[1]
              result[:success] = true
              Rails.logger.info "[SshConnectionService] Go is installed: #{result[:version]}"
            end
          else
            Rails.logger.info "[SshConnectionService] Go is not installed"
            result[:success] = true
          end

          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to check Go version: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
    end

    result
  end

  # Check if OSV Scanner is installed and return version
  def check_osv_scanner_version
    result = {
      success: false,
      installed: false,
      version: nil,
      error: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Checking OSV Scanner version on #{@server.name}"

      Timeout::timeout(CONNECTION_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # OSV Scanner is installed in the user's go/bin directory
          output = execute_command(ssh, "~/go/bin/osv-scanner --version 2>&1")

          if output && !output.downcase.include?('not found') && !output.downcase.include?('no such file')
            # Parse version from output like "osv-scanner version: v2.1.0"
            if match = output.match(/version:?\s*v?([\d.]+)/)
              result[:installed] = true
              result[:version] = "v#{match[1]}"
              result[:success] = true
              Rails.logger.info "[SshConnectionService] OSV Scanner is installed: #{result[:version]}"
            end
          else
            Rails.logger.info "[SshConnectionService] OSV Scanner is not installed"
            result[:success] = true
          end

          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to check OSV Scanner version: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
    end

    result
  end

  # Install Go programming language
  def install_go(version, server_uuid)
    result = {
      success: false,
      error: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Installing Go #{version} on #{@server.name}"
      Rails.logger.info "[SshConnectionService] Connection details - Host: #{@connection_details[:host]}, Port: #{@connection_details[:port]}, Username: #{@connection_details[:username]}"

      # Broadcast start message
      ActionCable.server.broadcast(
        "scanner_installation_#{server_uuid}",
        { type: 'output', message: "Starting Go installation (#{version})...\n" }
      )

      Rails.logger.info "[SshConnectionService] About to establish SSH connection with INSTALL_TIMEOUT=#{INSTALL_TIMEOUT}"

      Timeout::timeout(INSTALL_TIMEOUT) do
        Rails.logger.info "[SshConnectionService] Inside Timeout block, calling Net::SSH.start"

        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options(INSTALL_TIMEOUT)
        ) do |ssh|
          Rails.logger.info "[SshConnectionService] SSH connection established successfully"

          ActionCable.server.broadcast(
            "scanner_installation_#{server_uuid}",
            { type: 'output', message: "SSH connection established.\n" }
          )

          # Determine architecture (default to amd64)
          Rails.logger.info "[SshConnectionService] Detecting architecture"
          arch_output = execute_command(ssh, "uname -m 2>&1")
          arch = arch_output&.strip == "aarch64" ? "arm64" : "amd64"
          Rails.logger.info "[SshConnectionService] Architecture detected: #{arch}"

          filename = "#{version}.linux-#{arch}.tar.gz"
          download_url = "https://go.dev/dl/#{filename}"

          ActionCable.server.broadcast(
            "scanner_installation_#{server_uuid}",
            { type: 'output', message: "Detected architecture: #{arch}\n" }
          )

          # Download Go
          ActionCable.server.broadcast(
            "scanner_installation_#{server_uuid}",
            { type: 'output', message: "Downloading #{filename}...\n" }
          )

          download_output = execute_long_command(ssh, "wget #{download_url} 2>&1", 300) # 5 minutes for download

          if download_output&.downcase&.include?('error') || download_output&.downcase&.include?('failed')
            result[:error] = "Failed to download Go: #{download_output}"
            ActionCable.server.broadcast(
              "scanner_installation_#{server_uuid}",
              { type: 'error', message: result[:error] }
            )
            return result
          end

          ActionCable.server.broadcast(
            "scanner_installation_#{server_uuid}",
            { type: 'output', message: download_output || "Download completed.\n" }
          )

          # Remove old Go installation
          ActionCable.server.broadcast(
            "scanner_installation_#{server_uuid}",
            { type: 'output', message: "Removing old Go installation (if exists)...\n" }
          )
          execute_command(ssh, "sudo rm -rf /usr/local/go")

          # Extract new Go
          ActionCable.server.broadcast(
            "scanner_installation_#{server_uuid}",
            { type: 'output', message: "Extracting Go binaries...\n" }
          )
          extract_output = execute_long_command(ssh, "sudo tar -C /usr/local -xzf #{filename} 2>&1", 180) # 3 minutes for extraction

          if extract_output.present?
            ActionCable.server.broadcast(
              "scanner_installation_#{server_uuid}",
              { type: 'output', message: "Extraction completed.\n" }
            )
          end

          # Clean up downloaded file
          execute_command(ssh, "rm #{filename}")

          # Update PATH in .bashrc if not already there
          ActionCable.server.broadcast(
            "scanner_installation_#{server_uuid}",
            { type: 'output', message: "Configuring PATH...\n" }
          )

          execute_command(ssh, "grep -qxF 'export PATH=\$PATH:/usr/local/go/bin' ~/.bashrc || echo 'export PATH=\$PATH:/usr/local/go/bin' >> ~/.bashrc")
          execute_command(ssh, "grep -qxF 'export PATH=\$PATH:~/go/bin' ~/.bashrc || echo 'export PATH=\$PATH:~/go/bin' >> ~/.bashrc")

          # Verify installation
          version_output = execute_command(ssh, "/usr/local/go/bin/go version 2>&1")

          if version_output && version_output.include?(version)
            Rails.logger.info "[SshConnectionService] Go installed successfully: #{version_output}"
            result[:success] = true

            ActionCable.server.broadcast(
              "scanner_installation_#{server_uuid}",
              { type: 'success', message: "Go installed successfully: #{version_output}\n" }
            )
          else
            result[:error] = "Go installation verification failed: #{version_output}"
            ActionCable.server.broadcast(
              "scanner_installation_#{server_uuid}",
              { type: 'error', message: result[:error] }
            )
          end

          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue Net::SSH::ConnectionTimeout => e
      result[:error] = "SSH Connection timeout during Go installation"
      Rails.logger.error "[SshConnectionService] Net::SSH::ConnectionTimeout - Connection timed out while trying to connect"
      Rails.logger.error "[SshConnectionService] Exception: #{e.class} - #{e.message}"
      Rails.logger.error "[SshConnectionService] Backtrace: #{e.backtrace.first(10).join("\n")}"

      ActionCable.server.broadcast(
        "scanner_installation_#{server_uuid}",
        { type: 'error', message: "#{result[:error]}: #{e.message}" }
      )
    rescue Timeout::Error => e
      result[:error] = "Timeout during Go installation (exceeded #{INSTALL_TIMEOUT} seconds)"
      Rails.logger.error "[SshConnectionService] Timeout::Error - Operation took longer than #{INSTALL_TIMEOUT} seconds"
      Rails.logger.error "[SshConnectionService] Exception: #{e.class} - #{e.message}"
      Rails.logger.error "[SshConnectionService] Backtrace: #{e.backtrace.first(10).join("\n")}"

      ActionCable.server.broadcast(
        "scanner_installation_#{server_uuid}",
        { type: 'error', message: result[:error] }
      )
    rescue StandardError => e
      result[:error] = "Failed to install Go: #{e.class} - #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
      Rails.logger.error "[SshConnectionService] Full backtrace:"
      Rails.logger.error e.backtrace.join("\n")

      ActionCable.server.broadcast(
        "scanner_installation_#{server_uuid}",
        { type: 'error', message: result[:error] }
      )
    end

    result
  end

  # Install OSV Scanner
  def install_osv_scanner(server_uuid)
    result = {
      success: false,
      error: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Installing OSV Scanner on #{@server.name}"

      ActionCable.server.broadcast(
        "scanner_installation_#{server_uuid}",
        { type: 'output', message: "Starting OSV Scanner installation...\n" }
      )

      Timeout::timeout(INSTALL_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options(INSTALL_TIMEOUT)
        ) do |ssh|
          # Install OSV Scanner using go install
          ActionCable.server.broadcast(
            "scanner_installation_#{server_uuid}",
            { type: 'output', message: "Installing OSV Scanner via go install...\n" }
          )

          install_output = execute_long_command(ssh, "export PATH=\$PATH:/usr/local/go/bin:~/go/bin && /usr/local/go/bin/go install github.com/google/osv-scanner/v2/cmd/osv-scanner@v2 2>&1", 600) # 10 minutes for compilation

          if install_output.present?
            ActionCable.server.broadcast(
              "scanner_installation_#{server_uuid}",
              { type: 'output', message: install_output }
            )
          end

          # Verify installation
          ActionCable.server.broadcast(
            "scanner_installation_#{server_uuid}",
            { type: 'output', message: "Verifying installation...\n" }
          )

          version_output = execute_command(ssh, "export PATH=\$PATH:~/go/bin && ~/go/bin/osv-scanner --version 2>&1")

          if version_output && version_output.include?('version')
            Rails.logger.info "[SshConnectionService] OSV Scanner installed successfully: #{version_output}"
            result[:success] = true

            ActionCable.server.broadcast(
              "scanner_installation_#{server_uuid}",
              { type: 'success', message: "OSV Scanner installed successfully: #{version_output}\n" }
            )
          else
            result[:error] = "OSV Scanner installation verification failed: #{version_output}"
            ActionCable.server.broadcast(
              "scanner_installation_#{server_uuid}",
              { type: 'error', message: result[:error] }
            )
          end

          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to install OSV Scanner: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
      Rails.logger.error e.backtrace.join("\n")

      ActionCable.server.broadcast(
        "scanner_installation_#{server_uuid}",
        { type: 'error', message: result[:error] }
      )
    end

    result
  end

  private
  
  def ssh_options(custom_timeout = nil)
    options = {
      port: @connection_details[:port],
      timeout: custom_timeout || CONNECTION_TIMEOUT,
      verify_host_key: :never, # For development - in production you might want to verify
      non_interactive: true
    }

    # Initialize auth_methods array
    options[:auth_methods] = []

    # Prioritize password authentication if available
    if @connection_details[:password].present?
      options[:password] = @connection_details[:password]
      options[:auth_methods] << 'password'
    end

    # Add public key authentication if keys are available
    if @connection_details[:keys].present?
      options[:keys] = @connection_details[:keys]
      options[:auth_methods] << 'publickey'
    end

    # If no auth methods are configured, raise an error
    if options[:auth_methods].empty?
      raise StandardError, "No authentication method available (no SSH key or password configured)"
    end

    options
  end
  
  def gather_server_info(ssh)
    info = {}
    
    begin
      # Get OS information
      os_release = execute_command(ssh, "cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || uname -s")
      info[:os_version] = parse_os_version(os_release)
      
      # Get CPU information
      cpu_info = execute_command(ssh, "cat /proc/cpuinfo | head -20")
      info[:cpu_model] = parse_cpu_model(cpu_info)
      info[:cpu_cores] = parse_cpu_cores(cpu_info)
      
      # Get memory information
      mem_info = execute_command(ssh, "cat /proc/meminfo | head -5")
      info[:ram_total] = parse_memory(mem_info)
      
      # Get disk information
      disk_info = execute_command(ssh, "df -h / | tail -1")
      info[:disk_total] = parse_disk_info(disk_info)
      
      # Get uptime
      uptime = execute_command(ssh, "uptime")
      info[:uptime] = uptime&.strip
      
      # Get Dokku version
      dokku_version = execute_command(ssh, "dokku version 2>/dev/null")
      info[:dokku_version] = parse_dokku_version(dokku_version)
      
    rescue StandardError => e
      Rails.logger.error "Failed to gather server info: #{e.message}"
    end
    
    info
  end
  
  def execute_command(ssh, command)
    result = nil
    Timeout::timeout(COMMAND_TIMEOUT) do
      result = ssh.exec!(command)
    end
    result
  rescue Timeout::Error
    Rails.logger.error "Command timeout: #{command}"
    nil
  end
  
  def execute_long_command(ssh, command, timeout = UPDATE_TIMEOUT)
    result = nil
    Timeout::timeout(timeout) do
      result = ssh.exec!(command)
    end
    result
  rescue Timeout::Error
    Rails.logger.error "Long command timeout: #{command}"
    nil
  end
  
  def parse_os_version(os_release)
    return 'Unknown' if os_release.blank?
    
    # Try to extract from /etc/os-release
    if os_release.include?('PRETTY_NAME')
      match = os_release.match(/PRETTY_NAME="([^"]+)"/)
      return match[1] if match
    end
    
    # Fallback to first line
    os_release.lines.first&.strip || 'Unknown'
  end
  
  def parse_cpu_model(cpu_info)
    return 'Unknown' if cpu_info.blank?
    
    match = cpu_info.match(/model name\s*:\s*(.+)/)
    match ? match[1].strip : 'Unknown'
  end
  
  def parse_cpu_cores(cpu_info)
    return nil if cpu_info.blank?
    
    cores = cpu_info.scan(/processor\s*:/).count
    cores > 0 ? cores : nil
  end
  
  def parse_memory(mem_info)
    return 'Unknown' if mem_info.blank?
    
    match = mem_info.match(/MemTotal:\s*(\d+)\s*kB/)
    if match
      kb = match[1].to_i
      gb = (kb / 1024.0 / 1024.0).round(1)
      "#{gb} GB"
    else
      'Unknown'
    end
  end
  
  def parse_disk_info(disk_info)
    return 'Unknown' if disk_info.blank?
    
    # Extract total disk size from df output
    # Format: /dev/sda1  20G  5.5G   14G  30% /
    parts = disk_info.strip.split(/\s+/)
    return parts[1] if parts.length >= 2
    
    'Unknown'
  end
  
  def parse_dokku_version(dokku_output)
    return nil if dokku_output.blank?
    
    # Dokku version output format: "dokku version 0.30.1"
    # or newer format: "0.30.1"
    if dokku_output.match(/dokku version ([\d\.]+)/)
      $1
    elsif dokku_output.match(/^([\d\.]+)/)
      $1
    else
      # If we get any output from 'dokku version', Dokku is installed
      # but we couldn't parse the version
      dokku_output.strip.lines.first&.strip
    end
  end
  
  def update_server_info(info)
    @server.update!(
      os_version: info[:os_version],
      cpu_model: info[:cpu_model],
      cpu_cores: info[:cpu_cores],
      ram_total: info[:ram_total],
      disk_total: info[:disk_total],
      dokku_version: info[:dokku_version]
    )
  end
  
  def perform_system_update(ssh)
    update_output = ""
    
    # Set a longer timeout for update operations
    original_timeout = CONNECTION_TIMEOUT
    
    begin
      # Run apt update
      Rails.logger.info "Running apt update on #{@server.name}"
      update_output += "=== Running apt update ===\n"
      
      apt_update_result = execute_long_command(ssh, "sudo apt update 2>&1", 120) # 2 minutes for apt update
      update_output += apt_update_result if apt_update_result
      update_output += "\n"
      
      # Run apt upgrade
      Rails.logger.info "Running apt upgrade on #{@server.name}"
      update_output += "=== Running apt upgrade ===\n"
      
      # Use -y flag for non-interactive upgrade
      apt_upgrade_result = execute_long_command(ssh, "sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y 2>&1", 480) # 8 minutes for apt upgrade
      update_output += apt_upgrade_result if apt_upgrade_result
      update_output += "\n"
      
      # Check if reboot is required
      reboot_check = execute_command(ssh, "[ -f /var/run/reboot-required ] && echo 'REBOOT_REQUIRED' || echo 'NO_REBOOT'")
      if reboot_check&.include?('REBOOT_REQUIRED')
        update_output += "=== NOTICE ===\n"
        update_output += "A system reboot is required to complete some updates.\n"
        update_output += "Please reboot the server when convenient.\n"
      end
      
      Rails.logger.info "System update completed successfully on #{@server.name}"
      
    rescue StandardError => e
      Rails.logger.error "System update failed on #{@server.name}: #{e.message}"
      update_output += "\n=== ERROR ===\n"
      update_output += "Update process encountered an error: #{e.message}\n"
      raise e
    end
    
    update_output
  end
  
  def perform_server_restart(ssh)
    restart_output = ""
    
    begin
      Rails.logger.info "Initiating server restart on #{@server.name}"
      restart_output += "=== Server Restart Initiated ===\n"
      restart_output += "Executing: sudo shutdown -r now\n"
      restart_output += "Server will be unavailable for a few minutes while rebooting...\n\n"
      
      # Execute the restart command
      # Note: This command will likely disconnect the SSH session immediately
      restart_result = ssh.exec!("sudo shutdown -r now 2>&1")
      restart_output += restart_result if restart_result
      
      restart_output += "✅ Restart command executed successfully.\n"
      restart_output += "The server is now rebooting and will be unavailable until the restart completes.\n"
      
      Rails.logger.info "Server restart command executed successfully on #{@server.name}"
      
    rescue StandardError => e
      Rails.logger.error "Server restart failed on #{@server.name}: #{e.message}"
      restart_output += "\n=== ERROR ===\n"
      restart_output += "Restart process encountered an error: #{e.message}\n"
      # Don't re-raise the error since disconnection is expected during restart
    end
    
    restart_output
  end
  
  def perform_dokku_app_creation(ssh, app_name)
    creation_output = ""
    
    begin
      Rails.logger.info "Creating Dokku app '#{app_name}' on #{@server.name}"
      creation_output += "=== Creating Dokku App: #{app_name} ===\n"
      
      # Check if app already exists
      check_result = ssh.exec!("sudo dokku apps:list | grep '^#{app_name}$' || echo 'NOT_FOUND'")
      if check_result && !check_result.include?('NOT_FOUND')
        creation_output += "App '#{app_name}' already exists on this server.\n"
        return creation_output
      end
      
      # Create the Dokku app
      create_result = ssh.exec!("sudo dokku apps:create #{app_name} 2>&1")
      creation_output += create_result if create_result
      
      # Verify creation
      verify_result = ssh.exec!("sudo dokku apps:list | grep '^#{app_name}$' || echo 'CREATION_FAILED'")
      if verify_result && !verify_result.include?('CREATION_FAILED')
        creation_output += "\n✅ Dokku app '#{app_name}' created successfully!\n"
        creation_output += "The app is now ready for deployment.\n"
      else
        creation_output += "\n⚠️ App creation may have failed. Please check the output above.\n"
      end
      
      Rails.logger.info "Dokku app '#{app_name}' created successfully on #{@server.name}"
      
    rescue StandardError => e
      Rails.logger.error "Dokku app creation failed on #{@server.name}: #{e.message}"
      creation_output += "\n=== ERROR ===\n"
      creation_output += "App creation encountered an error: #{e.message}\n"
      raise e
    end
    
    creation_output
  end
  
  def perform_dokku_ssh_key_sync(ssh, public_keys)
    sync_output = ""
    
    begin
      Rails.logger.info "Syncing SSH keys to Dokku on #{@server.name}"
      sync_output += "=== Syncing SSH Keys to Dokku ===\n"
      
      # Backup current authorized_keys
      backup_result = ssh.exec!("sudo cp /home/dokku/.ssh/authorized_keys /home/dokku/.ssh/authorized_keys.backup.$(date +%s) 2>/dev/null || echo 'No existing keys to backup'")
      sync_output += "Backup: #{backup_result}\n" if backup_result
      
      # Clear current Dokku authorized_keys (keep admin key from system)
      clear_result = ssh.exec!("sudo bash -c 'grep \"# dokku\" /home/dokku/.ssh/authorized_keys > /tmp/dokku_system_keys 2>/dev/null || echo \"# System keys\" > /tmp/dokku_system_keys'")
      
      # Create new authorized_keys with system keys
      ssh.exec!("sudo cp /tmp/dokku_system_keys /home/dokku/.ssh/authorized_keys")
      
      if public_keys.any?
        sync_output += "Adding #{public_keys.count} SSH key#{'s' unless public_keys.count == 1}...\n"
        
        # Add each public key
        public_keys.each_with_index do |public_key, index|
          # Clean and validate the key
          clean_key = public_key.strip
          next if clean_key.empty?
          
          # Add comment to identify the key source
          key_with_comment = "#{clean_key} # vantage-deployed-key-#{index + 1}"
          
          # Append to authorized_keys
          append_result = ssh.exec!("sudo bash -c 'echo \"#{key_with_comment}\" >> /home/dokku/.ssh/authorized_keys'")
          sync_output += "Added key #{index + 1}\n"
        end
      else
        sync_output += "No SSH keys to add. Only system keys will remain.\n"
      end
      
      # Set proper permissions
      ssh.exec!("sudo chown dokku:dokku /home/dokku/.ssh/authorized_keys")
      ssh.exec!("sudo chmod 600 /home/dokku/.ssh/authorized_keys")
      
      # Verify the result
      verify_result = ssh.exec!("sudo wc -l /home/dokku/.ssh/authorized_keys")
      sync_output += "Final authorized_keys: #{verify_result}" if verify_result
      
      sync_output += "\n✅ SSH keys synchronized successfully!\n"
      sync_output += "Deployment access is now configured for the attached SSH keys.\n"
      
      Rails.logger.info "SSH keys synced successfully to Dokku on #{@server.name}"
      
    rescue StandardError => e
      Rails.logger.error "SSH key sync failed on #{@server.name}: #{e.message}"
      sync_output += "\n=== ERROR ===\n"
      sync_output += "SSH key sync encountered an error: #{e.message}\n"
      raise e
    end
    
    sync_output
  end
  
  def perform_dokku_installation(ssh)
    installation_output = ""
    dokku_version = AppSetting.dokku_install_version
    
    begin
      # Step 1: Copy our public key to the server
      installation_output += "=== Setting up SSH key ===\n"
      setup_output = setup_ssh_key(ssh)
      installation_output += setup_output
      installation_output += "\n"
      
      # Step 2: Check if Dokku is already installed
      installation_output += "=== Checking for existing Dokku installation ===\n"
      dokku_check = ssh.exec!("command -v dokku >/dev/null 2>&1 && echo 'DOKKU_EXISTS' || echo 'DOKKU_NOT_FOUND'")
      installation_output += dokku_check if dokku_check
      
      if dokku_check&.include?('DOKKU_EXISTS')
        installation_output += "Dokku is already installed on this server.\n"
        installation_output += "Checking version...\n"
        version_output = ssh.exec!("dokku version 2>/dev/null")
        installation_output += version_output if version_output
        return installation_output
      end
      
      # Step 3: Download Dokku bootstrap script
      installation_output += "\n=== Downloading Dokku v#{dokku_version} bootstrap script ===\n"
      download_cmd = "wget -NP . https://dokku.com/install/v#{dokku_version}/bootstrap.sh"
      download_output = execute_long_command(ssh, download_cmd, 120) # 2 minutes for download
      installation_output += download_output if download_output
      installation_output += "\n"
      
      # Step 4: Install Dokku
      installation_output += "=== Installing Dokku v#{dokku_version} ===\n"
      installation_output += "This may take several minutes...\n"
      
      install_cmd = "sudo DOKKU_TAG=v#{dokku_version} bash bootstrap.sh"
      install_output = execute_long_command(ssh, install_cmd, 720) # 12 minutes for installation
      installation_output += install_output if install_output
      installation_output += "\n"
      
      # Step 5: Verify installation
      installation_output += "=== Verifying Dokku installation ===\n"
      verify_output = execute_command(ssh, "dokku version 2>/dev/null")
      if verify_output
        installation_output += verify_output
        installation_output += "\n✅ Dokku installation completed successfully!\n"
      else
        installation_output += "⚠️ Dokku installation may have failed. Please check the logs above.\n"
      end
      
      # Step 6: Set up initial configuration
      installation_output += "\n=== Setting up initial Dokku configuration ===\n"
      setup_dokku_output = setup_initial_dokku_config(ssh)
      installation_output += setup_dokku_output
      
      Rails.logger.info "Dokku installation completed successfully on #{@server.name}"
      
    rescue StandardError => e
      Rails.logger.error "Dokku installation failed on #{@server.name}: #{e.message}"
      installation_output += "\n=== ERROR ===\n"
      installation_output += "Installation process encountered an error: #{e.message}\n"
      raise e
    end
    
    installation_output
  end
  
  def setup_ssh_key(ssh)
    setup_output = ""
    
    return "⚠️ No public key configured in environment variables.\n" unless ENV['DOKKU_SSH_PUBLIC_KEY'].present?
    
    public_key = ENV['DOKKU_SSH_PUBLIC_KEY'].strip
    
    # Create .ssh directory if it doesn't exist
    ssh.exec!("mkdir -p ~/.ssh")
    ssh.exec!("chmod 700 ~/.ssh")
    
    # Add our public key to authorized_keys
    add_key_cmd = "echo '#{public_key}' >> ~/.ssh/authorized_keys"
    setup_output += ssh.exec!(add_key_cmd) || ""
    
    # Set proper permissions
    ssh.exec!("chmod 600 ~/.ssh/authorized_keys")
    ssh.exec!("chown -R $USER:$USER ~/.ssh")
    
    setup_output += "✅ SSH public key added to authorized_keys\n"
    setup_output
  end
  
  def setup_initial_dokku_config(ssh)
    config_output = ""

    # Set up the public key for Dokku (if we have one)
    if ENV['DOKKU_SSH_PUBLIC_KEY'].present?
      public_key = ENV['DOKKU_SSH_PUBLIC_KEY'].strip

      # Add the public key to Dokku
      add_key_to_dokku = "echo '#{public_key}' | sudo dokku ssh-keys:add admin"
      config_output += ssh.exec!(add_key_to_dokku) || ""
      config_output += "✅ SSH key added to Dokku for admin user\n"
    end

    # Set global Let's Encrypt email for all apps on this server
    if ENV['DOKKU_LETSENCRYPT_EMAIL'].present?
      email = ENV['DOKKU_LETSENCRYPT_EMAIL'].strip
      config_output += "\n=== Configuring Let's Encrypt Global Email ===\n"

      # First install the Let's Encrypt plugin if not already installed
      config_output += "Installing Let's Encrypt plugin...\n"
      install_plugin = ssh.exec!("sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git 2>&1 || echo 'Plugin already installed'")
      config_output += install_plugin || ""

      # Set the global email for Let's Encrypt
      set_email_cmd = "sudo dokku letsencrypt:set --global email #{email}"
      email_output = ssh.exec!(set_email_cmd)
      config_output += email_output || ""
      config_output += "\n✅ Let's Encrypt global email set to: #{email}\n"
    else
      config_output += "\n⚠️ DOKKU_LETSENCRYPT_EMAIL not configured - SSL certificates will require manual email setup\n"
    end

    # Set global domain (optional, can be configured later)
    # config_output += ssh.exec!("sudo dokku domains:set-global #{@server.ip}.nip.io") || ""

    config_output += "\n✅ Initial Dokku configuration completed\n"
    config_output += "\nNext steps:\n"
    config_output += "- Access Dokku at: http://#{@server.ip}\n"
    config_output += "- Use 'dokku apps:create myapp' to create your first app\n"
    config_output += "- Configure domains with 'dokku domains:set myapp yourdomain.com'\n"

    config_output
  end
  
  def gather_server_info_after_install(ssh)
    # Re-gather server info including the new Dokku version
    info = {}
    
    begin
      # Get updated Dokku version
      dokku_version = execute_command(ssh, "dokku version 2>/dev/null")
      info[:dokku_version] = parse_dokku_version(dokku_version)
      
      # Update server with new Dokku version
      @server.update!(dokku_version: info[:dokku_version]) if info[:dokku_version]
      
    rescue StandardError => e
      Rails.logger.error "Failed to gather server info after Dokku install: #{e.message}"
    end
  end
  
  def perform_dokku_env_sync(ssh, app_name, env_vars)
    sync_output = ""
    
    begin
      Rails.logger.info "Syncing environment variables to Dokku app '#{app_name}' on #{@server.name}"
      sync_output += "=== Syncing Environment Variables to Dokku App: #{app_name} ===\n"
      
      # Check if app exists
      app_check = ssh.exec!("sudo dokku apps:list | grep '^#{app_name}$' || echo 'APP_NOT_FOUND'")
      if app_check&.include?('APP_NOT_FOUND')
        sync_output += "⚠️ App '#{app_name}' does not exist. Creating it first...\n"
        create_result = ssh.exec!("sudo dokku apps:create #{app_name} 2>&1")
        sync_output += create_result if create_result
        sync_output += "\n"
      end
      
      if env_vars.any?
        sync_output += "Setting #{env_vars.count} environment variable#{'s' unless env_vars.count == 1}...\n"
        
        # Build the config:set command with all variables
        env_string = env_vars.map { |key, value| "#{key}=#{shell_escape(value)}" }.join(' ')
        config_cmd = "sudo dokku config:set #{app_name} #{env_string}"
        
        # Execute the command
        config_result = ssh.exec!(config_cmd + " 2>&1")
        sync_output += config_result if config_result
        sync_output += "\n"
        
        # Verify the configuration
        verify_result = ssh.exec!("sudo dokku config:show #{app_name}")
        if verify_result
          sync_output += "=== Current Configuration ===\n"
          sync_output += verify_result
          sync_output += "\n"
        end
        
        sync_output += "✅ Environment variables synchronized successfully!\n"
        sync_output += "Variables are now available in the Dokku app environment.\n"
      else
        sync_output += "No environment variables to set.\n"
        sync_output += "Current app configuration remains unchanged.\n"
      end
      
      Rails.logger.info "Environment variables synced successfully to Dokku app '#{app_name}' on #{@server.name}"
      
    rescue StandardError => e
      Rails.logger.error "Environment variables sync failed on #{@server.name}: #{e.message}"
      sync_output += "\n=== ERROR ===\n"
      sync_output += "Environment variables sync encountered an error: #{e.message}\n"
      raise e
    end
    
    sync_output
  end
  
  def perform_dokku_domain_sync(ssh, app_name, domain_names)
    sync_output = ""
    
    begin
      Rails.logger.info "Syncing domains to Dokku app '#{app_name}' on #{@server.name}"
      sync_output += "=== Syncing Domains to Dokku App: #{app_name} ===\n"
      
      # Check if app exists
      app_check = execute_command(ssh, "sudo dokku apps:list | grep '^#{app_name}$' || echo 'APP_NOT_FOUND'")
      if app_check&.include?('APP_NOT_FOUND')
        sync_output += "⚠️ App '#{app_name}' does not exist. Creating it first...\n"
        create_result = execute_command(ssh, "sudo dokku apps:create #{app_name} 2>&1")
        sync_output += create_result if create_result
        sync_output += "\n"
      end
      
      if domain_names.any?
        sync_output += "Setting #{domain_names.count} domain#{'s' unless domain_names.count == 1}...\n"

        # First, clear existing domains to avoid conflicts
        clear_cmd = "sudo dokku domains:clear #{app_name}"
        clear_result = execute_command(ssh, clear_cmd + " 2>&1")
        sync_output += "Clearing existing domains...\n"

        # Set all domains at once
        domains_string = domain_names.join(' ')
        domains_cmd = "sudo dokku domains:set #{app_name} #{domains_string}"

        # Execute the domains command
        domains_result = execute_command(ssh, domains_cmd + " 2>&1")
        sync_output += "Domain configuration:\n#{domains_result}\n" if domains_result

        # Now configure SSL for ALL domains at once
        sync_output += "\n=== Configuring SSL for all domains ===\n"

        # Install letsencrypt plugin if not already installed
        letsencrypt_check = execute_command(ssh, "sudo dokku plugin:list | grep letsencrypt || echo 'NOT_INSTALLED'")
        if letsencrypt_check&.include?('NOT_INSTALLED')
          sync_output += "Installing Let's Encrypt plugin...\n"
          install_result = execute_long_command(ssh, "sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git 2>&1", 300) # 5 minutes for plugin install
          sync_output += install_result if install_result
          sync_output += "\n"
        end

        # First, disable SSL if it was previously enabled (to clear old certificates)
        sync_output += "Cleaning up any existing SSL configuration...\n"
        disable_ssl_cmd = "sudo dokku letsencrypt:disable #{app_name}"
        disable_result = execute_command(ssh, disable_ssl_cmd + " 2>&1")
        # Don't show error if SSL wasn't enabled before

        # Use configured Let's Encrypt email if available
        letsencrypt_email = ENV['DOKKU_LETSENCRYPT_EMAIL']

        if letsencrypt_email.present?
          sync_output += "Setting Let's Encrypt email to: #{letsencrypt_email}\n"
          # Set the email at app level to ensure it's used
          email_cmd = "sudo dokku letsencrypt:set #{app_name} email #{letsencrypt_email}"
          email_result = execute_command(ssh, email_cmd + " 2>&1")
          sync_output += email_result if email_result && email_result.include?("Setting")
        else
          sync_output += "⚠️ Warning: DOKKU_LETSENCRYPT_EMAIL not configured\n"
          sync_output += "Using server's global Let's Encrypt email configuration\n"
        end

        # Ensure the app doesn't have a conflicting server setting
        clear_server_cmd = "sudo dokku letsencrypt:set #{app_name} server"
        execute_command(ssh, clear_server_cmd + " 2>&1")

        # Note: Don't set the server unless using staging for testing
        # The default production server is what we want
        # For testing you could use: https://acme-staging-v02.api.letsencrypt.org/directory

        # Enable auto-renewal
        auto_renew_cmd = "sudo dokku letsencrypt:set #{app_name} auto-renew true"
        auto_renew_result = execute_command(ssh, auto_renew_cmd + " 2>&1")
        sync_output += "Enabling auto-renewal...\n"

        # Enable SSL for ALL domains at once (this is the key - run ONCE after all domains are set)
        sync_output += "\nRequesting SSL certificates for all domains...\n"
        sync_output += "This may take a few minutes while Let's Encrypt validates the domains...\n"
        ssl_cmd = "sudo dokku letsencrypt:enable #{app_name}"
        ssl_result = execute_long_command(ssh, ssl_cmd + " 2>&1", 300) # 5 minutes for SSL certificate generation

        if ssl_result
          sync_output += "SSL Result:\n#{ssl_result}\n"

          # Check if SSL was successful
          if ssl_result.include?("Certificate retrieved successfully") || ssl_result.include?("done")
            sync_output += "✅ SSL certificates generated successfully for all domains!\n"
          elsif ssl_result.include?("already exists")
            sync_output += "✅ SSL certificates already exist and are valid.\n"
          else
            sync_output += "⚠️ SSL configuration may have encountered issues.\n"
            sync_output += "Common causes:\n"
            sync_output += "• DNS A records not pointing to #{@server.ip}\n"
            sync_output += "• Port 80/443 not accessible from internet\n"
            sync_output += "• Rate limiting (too many certificate requests)\n"
          end
        end
        
        # Verify final domain configuration
        verify_result = execute_command(ssh, "sudo dokku domains:report #{app_name}")
        if verify_result
          sync_output += "\n=== Final Domain Configuration ===\n"
          sync_output += verify_result
          sync_output += "\n"
        end

        # Check SSL status
        ssl_status = execute_command(ssh, "sudo dokku letsencrypt:list | grep #{app_name} || echo 'NO_SSL'")
        if ssl_status && !ssl_status.include?('NO_SSL')
          sync_output += "=== SSL Status ===\n"
          sync_output += ssl_status
          sync_output += "\n"
        end

        # Show nginx ports to verify SSL is active
        ports_check = execute_command(ssh, "sudo dokku proxy:ports #{app_name} 2>&1")
        if ports_check
          sync_output += "=== Port Configuration ===\n"
          sync_output += ports_check
          sync_output += "\n"
        end

        sync_output += "\n✅ Domain configuration completed!\n"
        sync_output += "Domains are now configured with SSL certificates.\n"
        sync_output += "\n📋 Important Notes:\n"
        sync_output += "• Ensure DNS A records point to #{@server.ip}\n"
        sync_output += "• SSL certificates are shared per app, not per domain\n"
        sync_output += "• Auto-renewal is enabled (certificates renew automatically)\n"
      else
        # Clear all domains (reset to default)
        clear_cmd = "sudo dokku domains:clear #{app_name}"
        clear_result = execute_command(ssh, clear_cmd + " 2>&1")
        sync_output += "Cleared all custom domains:\n#{clear_result}\n" if clear_result
        sync_output += "App will use default Dokku domain.\n"
      end
      
      Rails.logger.info "Domains synced successfully to Dokku app '#{app_name}' on #{@server.name}"
      
    rescue StandardError => e
      Rails.logger.error "Domain sync failed on #{@server.name}: #{e.message}"
      sync_output += "\n=== ERROR ===\n"
      sync_output += "Domain sync encountered an error: #{e.message}\n"
      raise e
    end
    
    sync_output
  end
  
  def perform_database_configuration(ssh, app_name, database_config)
    config_output = ""
    database_url = nil
    redis_url = nil

    begin
      Rails.logger.info "Configuring database for Dokku app '#{app_name}' on #{@server.name}"
      config_output += "=== Configuring Database for Dokku App: #{app_name} ===\n"
      
      # Check if app exists
      app_check = execute_command(ssh, "sudo dokku apps:list | grep '^#{app_name}$' || echo 'APP_NOT_FOUND'")
      if app_check&.include?('APP_NOT_FOUND')
        config_output += "⚠️ App '#{app_name}' does not exist. Creating it first...\n"
        create_result = execute_command(ssh, "sudo dokku apps:create #{app_name} 2>&1")
        config_output += create_result if create_result
        config_output += "\n"
      end
      
      # Install database plugin
      db_type = database_config.database_type
      plugin_url = database_config.plugin_url
      
      config_output += "\n=== Installing #{database_config.display_name} Plugin ===\n"
      plugin_check = execute_command(ssh, "sudo dokku plugin:list | grep #{db_type} || echo 'NOT_INSTALLED'")
      
      if plugin_check&.include?('NOT_INSTALLED')
        config_output += "Installing #{database_config.display_name} plugin...\n"
        install_result = execute_long_command(ssh, "sudo dokku plugin:install #{plugin_url} 2>&1", 300)
        config_output += install_result if install_result
        config_output += "\n"
      else
        config_output += "#{database_config.display_name} plugin already installed.\n"
      end
      
      # Create database
      db_name = database_config.database_name
      config_output += "\n=== Creating #{database_config.display_name} Database: #{db_name} ===\n"
      
      # Check if database already exists
      db_check = execute_command(ssh, "sudo dokku #{db_type}:list | grep '^#{db_name}$' || echo 'NOT_FOUND'")
      if db_check&.include?('NOT_FOUND')
        config_output += "Creating database '#{db_name}'...\n"
        create_db_result = execute_long_command(ssh, "sudo dokku #{db_type}:create #{db_name} 2>&1", 300)
        config_output += create_db_result if create_db_result
        config_output += "\n"
      else
        config_output += "Database '#{db_name}' already exists.\n"
      end
      
      # Link database to app
      config_output += "=== Linking Database to App ===\n"
      link_result = execute_command(ssh, "sudo dokku #{db_type}:link #{db_name} #{app_name} 2>&1")
      config_output += link_result if link_result
      config_output += "\n"
      
      # Ensure DATABASE_URL environment variable is set
      config_output += "=== Setting Database Environment Variable ===\n"
      db_url_result = execute_command(ssh, "sudo dokku #{db_type}:info #{db_name} --dsn 2>&1")
      if db_url_result && !db_url_result.include?('ERROR') && !db_url_result.strip.empty?
        database_url = db_url_result.strip
        config_output += "Retrieved database URL: #{database_url[0..20]}...\n"
        
        # Set the DATABASE_URL environment variable
        set_env_result = execute_command(ssh, "sudo dokku config:set #{app_name} DATABASE_URL='#{database_url}' 2>&1")
        config_output += set_env_result if set_env_result
        config_output += "DATABASE_URL environment variable set successfully.\n"
      else
        config_output += "Warning: Could not retrieve database URL automatically. Link command should have set it.\n"
      end
      config_output += "\n"
      
      # Configure Redis if enabled
      if database_config.redis_enabled?
        redis_name = database_config.redis_name
        config_output += "\n=== Installing Redis Plugin ===\n"
        
        redis_plugin_check = execute_command(ssh, "sudo dokku plugin:list | grep redis || echo 'NOT_INSTALLED'")
        if redis_plugin_check&.include?('NOT_INSTALLED')
          config_output += "Installing Redis plugin...\n"
          redis_install_result = execute_long_command(ssh, "sudo dokku plugin:install #{database_config.redis_plugin_url} 2>&1", 300)
          config_output += redis_install_result if redis_install_result
          config_output += "\n"
        else
          config_output += "Redis plugin already installed.\n"
        end
        
        config_output += "=== Creating Redis Instance: #{redis_name} ===\n"
        redis_check = execute_command(ssh, "sudo dokku redis:list | grep '^#{redis_name}$' || echo 'NOT_FOUND'")
        if redis_check&.include?('NOT_FOUND')
          config_output += "Creating Redis instance '#{redis_name}'...\n"
          create_redis_result = execute_long_command(ssh, "sudo dokku redis:create #{redis_name} 2>&1", 180)
          config_output += create_redis_result if create_redis_result
          config_output += "\n"
        else
          config_output += "Redis instance '#{redis_name}' already exists.\n"
        end
        
        # Link Redis to app
        config_output += "=== Linking Redis to App ===\n"
        redis_link_result = execute_command(ssh, "sudo dokku redis:link #{redis_name} #{app_name} 2>&1")
        config_output += redis_link_result if redis_link_result
        config_output += "\n"
        
        # Ensure REDIS_URL environment variable is set
        config_output += "=== Setting Redis Environment Variable ===\n"
        redis_url_result = execute_command(ssh, "sudo dokku redis:info #{redis_name} --dsn 2>&1")
        if redis_url_result && !redis_url_result.include?('ERROR') && !redis_url_result.strip.empty?
          redis_url = redis_url_result.strip
          config_output += "Retrieved Redis URL: #{redis_url[0..20]}...\n"
          
          # Set the REDIS_URL environment variable
          set_redis_env_result = execute_command(ssh, "sudo dokku config:set #{app_name} REDIS_URL='#{redis_url}' 2>&1")
          config_output += set_redis_env_result if set_redis_env_result
          config_output += "REDIS_URL environment variable set successfully.\n"
        else
          config_output += "Warning: Could not retrieve Redis URL automatically. Link command should have set it.\n"
        end
        config_output += "\n"
      end
      
      # Show final configuration
      config_output += "\n=== Final Configuration ===\n"
      env_result = execute_command(ssh, "sudo dokku config:show #{app_name}")
      if env_result
        config_output += "Environment variables:\n#{env_result}\n"
      end
      
      config_output += "\n✅ Database configuration completed successfully!\n"
      config_output += "#{database_config.display_name} database '#{db_name}' is now linked to '#{app_name}'.\n"
      if database_config.redis_enabled?
        config_output += "Redis instance '#{database_config.redis_name}' is also linked to the app.\n"
      end
      config_output += "Database connection details are available as environment variables.\n"
      
      Rails.logger.info "Database configured successfully for Dokku app '#{app_name}' on #{@server.name}"
      
    rescue StandardError => e
      Rails.logger.error "Database configuration failed on #{@server.name}: #{e.message}"
      config_output += "\n=== ERROR ===\n"
      config_output += "Database configuration encountered an error: #{e.message}\n"
      raise e
    end

    {
      output: config_output,
      database_url: database_url,
      redis_url: redis_url
    }
  end
  
  def perform_database_deletion(ssh, app_name, database_config)
    deletion_output = ""
    
    begin
      Rails.logger.info "Deleting database configuration for Dokku app '#{app_name}' on #{@server.name}"
      deletion_output += "=== Deleting Database Configuration for Dokku App: #{app_name} ===\n"
      
      db_type = database_config.database_type
      db_name = database_config.database_name
      
      # Remove environment variables first
      deletion_output += "\n=== Removing Environment Variables ===\n"
      
      # Remove DATABASE_URL
      env_var_name = database_config.environment_variable_name
      if env_var_name
        deletion_output += "Removing #{env_var_name} environment variable...\n"
        unset_result = execute_command(ssh, "sudo dokku config:unset #{app_name} #{env_var_name} 2>&1")
        deletion_output += unset_result if unset_result
      end
      
      # Remove REDIS_URL if Redis is enabled
      if database_config.redis_enabled?
        redis_env_var = database_config.redis_environment_variable_name
        if redis_env_var
          deletion_output += "Removing #{redis_env_var} environment variable...\n"
          unset_redis_result = execute_command(ssh, "sudo dokku config:unset #{app_name} #{redis_env_var} 2>&1")
          deletion_output += unset_redis_result if unset_redis_result
        end
      end
      deletion_output += "\n"
      
      # Detach and delete Redis if enabled
      if database_config.redis_enabled?
        redis_name = database_config.redis_name
        deletion_output += "=== Detaching and Deleting Redis Instance: #{redis_name} ===\n"
        
        # Unlink Redis from app
        deletion_output += "Unlinking Redis from app...\n"
        redis_unlink_result = execute_command(ssh, "sudo dokku redis:unlink #{redis_name} #{app_name} 2>&1")
        deletion_output += redis_unlink_result if redis_unlink_result
        
        # Delete Redis instance
        deletion_output += "Deleting Redis instance...\n"
        redis_delete_result = execute_command(ssh, "sudo dokku redis:destroy #{redis_name} --force 2>&1")
        deletion_output += redis_delete_result if redis_delete_result
        deletion_output += "\n"
      end
      
      # Detach and delete database
      deletion_output += "=== Detaching and Deleting #{database_config.display_name} Database: #{db_name} ===\n"
      
      # Unlink database from app
      deletion_output += "Unlinking database from app...\n"
      unlink_result = execute_command(ssh, "sudo dokku #{db_type}:unlink #{db_name} #{app_name} 2>&1")
      deletion_output += unlink_result if unlink_result
      
      # Delete database
      deletion_output += "Deleting database...\n"
      delete_result = execute_command(ssh, "sudo dokku #{db_type}:destroy #{db_name} --force 2>&1")
      deletion_output += delete_result if delete_result
      deletion_output += "\n"
      
      # Show final configuration
      deletion_output += "=== Final Configuration ===\n"
      env_result = execute_command(ssh, "sudo dokku config:show #{app_name}")
      if env_result
        deletion_output += "Remaining environment variables:\n#{env_result}\n"
      end
      
      deletion_output += "\n✅ Database configuration deleted successfully!\n"
      deletion_output += "#{database_config.display_name} database '#{db_name}' has been detached and deleted.\n"
      if database_config.redis_enabled?
        deletion_output += "Redis instance '#{database_config.redis_name}' has also been detached and deleted.\n"
      end
      deletion_output += "All related environment variables have been removed.\n"
      
      Rails.logger.info "Database configuration deleted successfully for Dokku app '#{app_name}' on #{@server.name}"
      
    rescue StandardError => e
      Rails.logger.error "Database deletion failed on #{@server.name}: #{e.message}"
      deletion_output += "\n=== ERROR ===\n"
      deletion_output += "Database deletion encountered an error: #{e.message}\n"
      raise e
    end
    
    deletion_output
  end
  
  def shell_escape(value)
    # Escape shell special characters in environment variable values
    return '""' if value.nil? || value.empty?

    # Use single quotes to avoid most shell interpretation, but handle single quotes in the value
    if value.include?("'")
      # If the value contains single quotes, we need to use double quotes and escape what's needed
      escaped = value.gsub('\\', '\\\\').gsub('"', '\\"').gsub('$', '\\$').gsub('`', '\\`')
      "\"#{escaped}\""
    else
      # Simple case: wrap in single quotes
      "'#{value}'"
    end
  end

  # List all Dokku apps on the server
  def list_dokku_apps
    result = {
      success: false,
      apps: [],
      error: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Listing Dokku apps on #{@server.name}"

      Timeout::timeout(CONNECTION_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          output = execute_command(ssh, "dokku apps:list 2>&1")

          if output && !output.downcase.include?('error')
            # Skip the header line (=====> My Apps) and get app names
            apps = output.split("\n").select { |line| !line.include?('====>') && line.strip.present? }.map(&:strip)
            result[:apps] = apps
            result[:success] = true
            Rails.logger.info "[SshConnectionService] Found #{apps.count} Dokku apps"
          else
            result[:error] = output || "Failed to list apps"
            Rails.logger.error "[SshConnectionService] #{result[:error]}"
          end

          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to list Dokku apps: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
    end

    result
  end

  # Check if Dokku app is running and get container info
  def check_app_running(app_name)
    result = {
      success: false,
      running: false,
      container_id: nil,
      workdir: nil,
      error: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Checking if #{app_name} is running on #{@server.name}"

      Timeout::timeout(CONNECTION_TIMEOUT) do
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options
        ) do |ssh|
          # Check if app is running
          status_output = execute_command(ssh, "dokku ps:report #{app_name} | grep 'Status web' 2>&1")

          if status_output && status_output.include?('running')
            result[:running] = true

            # Get container ID
            cid_output = execute_command(ssh, "dokku ps:report #{app_name} | grep 'CID:' | awk '{print $NF}' | tr -d ')' 2>&1")

            if cid_output && !cid_output.strip.empty?
              container_id = cid_output.strip
              result[:container_id] = container_id

              # Get working directory from container
              workdir_output = execute_command(ssh, "docker inspect #{container_id} --format='{{.Config.WorkingDir}}' 2>&1")

              if workdir_output && !workdir_output.strip.empty? && !workdir_output.include?('Error')
                result[:workdir] = workdir_output.strip
                result[:success] = true
                Rails.logger.info "[SshConnectionService] #{app_name} is running with container #{container_id} at #{result[:workdir]}"
              else
                result[:error] = "Failed to get working directory"
                Rails.logger.error "[SshConnectionService] #{result[:error]}"
              end
            else
              result[:error] = "Failed to get container ID"
              Rails.logger.error "[SshConnectionService] #{result[:error]}"
            end
          else
            result[:error] = "App is not running"
            Rails.logger.info "[SshConnectionService] #{app_name} is not running"
          end

          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to check app status: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
    end

    result
  end

  # Run OSV scanner on a Dokku app using container copy approach
  def run_osv_scanner_on_container(app_name)
    result = {
      success: false,
      raw_output: nil,
      error: nil
    }

    begin
      Rails.logger.info "[SshConnectionService] Running OSV scanner for #{app_name} on #{@server.name}"

      Timeout::timeout(COMMAND_TIMEOUT * 3) do # Give extra time for copy + scan
        Net::SSH.start(
          @connection_details[:host],
          @connection_details[:username],
          ssh_options(COMMAND_TIMEOUT * 3)
        ) do |ssh|
          # Step 1: Check if app is running and get container info
          app_info = check_app_running(app_name)

          unless app_info[:success] && app_info[:running]
            result[:error] = app_info[:error] || "App is not running"
            return result
          end

          container_id = app_info[:container_id]
          workdir = app_info[:workdir] || '/app'

          # Step 2: Create temporary directory for scanning
          temp_dir = "/tmp/#{app_name}-scan-#{Time.now.to_i}"
          execute_command(ssh, "mkdir -p #{temp_dir}")

          # Step 3: Copy container content to temp directory
          Rails.logger.info "[SshConnectionService] Copying container #{container_id}:#{workdir} to #{temp_dir}"
          copy_output = execute_long_command(ssh, "docker cp #{container_id}:#{workdir} #{temp_dir} 2>&1", 120)

          if copy_output && copy_output.downcase.include?('error')
            result[:error] = "Failed to copy container content: #{copy_output}"
            execute_command(ssh, "rm -rf #{temp_dir}") # Clean up
            return result
          end

          # Step 4: Run OSV scanner on the copied content
          Rails.logger.info "[SshConnectionService] Running OSV scanner on #{temp_dir}"
          scan_command = "export PATH=$PATH:~/go/bin && osv-scanner scan #{temp_dir} 2>&1"
          scan_output = execute_long_command(ssh, scan_command, 300) # 5 minutes for scan

          # Step 5: Clean up temp directory
          Rails.logger.info "[SshConnectionService] Cleaning up #{temp_dir}"
          execute_command(ssh, "rm -rf #{temp_dir}")

          result[:raw_output] = scan_output || "No output from scanner"
          result[:success] = true
          Rails.logger.info "[SshConnectionService] OSV scan completed for #{app_name}"

          @server.update!(last_connected_at: Time.current)
        end
      end
    rescue StandardError => e
      result[:error] = "Failed to run OSV scanner: #{e.message}"
      Rails.logger.error "[SshConnectionService] #{result[:error]}"
    end

    result
  end

  # Perform a complete vulnerability scan for a deployment
  def perform_vulnerability_scan(deployment, scan_type = 'manual')
    scan = VulnerabilityScan.create!(
      deployment: deployment,
      server: @server,
      status: 'running',
      scan_type: scan_type,
      started_at: Time.current
    )

    begin
      Rails.logger.info "[SshConnectionService] Starting vulnerability scan for #{deployment.dokku_app_name}"

      # Step 1: Check if app is running
      app_info = check_app_running(deployment.dokku_app_name)

      unless app_info[:success] && app_info[:running]
        error_message = app_info[:error] || "App is not running"
        scan.update!(
          status: 'failed',
          completed_at: Time.current,
          summary: error_message
        )
        return { success: false, scan: scan, error: error_message }
      end

      # Step 2: Run OSV scanner on container
      scan_result = run_osv_scanner_on_container(deployment.dokku_app_name)

      unless scan_result[:success]
        raise StandardError, scan_result[:error]
      end

      # Step 3: Parse results
      parser = OsvScannerParser.new(scan_result[:raw_output])
      parsed_data = parser.parse

      # Step 4: Update scan record
      scan.update!(
        status: 'completed',
        completed_at: Time.current,
        total_packages: parsed_data[:total_packages],
        vulnerabilities_found: parsed_data[:vulnerabilities_found],
        critical_count: parsed_data[:severity_counts][:critical],
        high_count: parsed_data[:severity_counts][:high],
        medium_count: parsed_data[:severity_counts][:medium],
        low_count: parsed_data[:severity_counts][:low],
        unknown_count: parsed_data[:severity_counts][:unknown],
        raw_output: scan_result[:raw_output],
        summary: parsed_data[:summary]
      )

      # Step 5: Create vulnerability records
      parsed_data[:vulnerabilities].each do |vuln_data|
        scan.vulnerabilities.create!(
          osv_id: vuln_data[:osv_id],
          cvss_score: vuln_data[:cvss_score],
          ecosystem: vuln_data[:ecosystem],
          package_name: vuln_data[:package_name],
          current_version: vuln_data[:current_version],
          fixed_version: vuln_data[:fixed_version],
          severity: vuln_data[:severity],
          source_file: vuln_data[:source_file],
          osv_url: vuln_data[:osv_url]
        )
      end

      Rails.logger.info "[SshConnectionService] Vulnerability scan completed for #{deployment.dokku_app_name}: #{parsed_data[:vulnerabilities_found]} vulnerabilities found"

      { success: true, scan: scan }
    rescue StandardError => e
      Rails.logger.error "[SshConnectionService] Vulnerability scan failed: #{e.message}"

      scan.update!(
        status: 'failed',
        completed_at: Time.current,
        summary: "Scan failed: #{e.message}"
      )

      { success: false, scan: scan, error: e.message }
    end
  end
end