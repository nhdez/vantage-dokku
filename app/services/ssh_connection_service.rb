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
      database_urls: {}
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
          result[:database_urls] = config_result[:database_urls]
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
  
  private
  
  def ssh_options
    options = {
      port: @connection_details[:port],
      timeout: CONNECTION_TIMEOUT,
      verify_host_key: :never, # For development - in production you might want to verify
      non_interactive: true
    }
    
    # Try SSH key first if available
    if @connection_details[:keys].present?
      options[:keys] = @connection_details[:keys]
      options[:auth_methods] = ['publickey']
      
      # Add password as fallback if available
      if @connection_details[:password].present?
        options[:password] = @connection_details[:password]
        options[:auth_methods] << 'password'
      end
    elsif @connection_details[:password].present?
      # Only password authentication
      options[:password] = @connection_details[:password]
      options[:auth_methods] = ['password']
    else
      # No authentication method available
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
    
    # Set global domain (optional, can be configured later)
    # config_output += ssh.exec!("sudo dokku domains:set-global #{@server.ip}.nip.io") || ""
    
    config_output += "✅ Initial Dokku configuration completed\n"
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
        
        # Clear existing domains and set new ones
        domains_string = domain_names.join(' ')
        domains_cmd = "sudo dokku domains:set #{app_name} #{domains_string}"
        
        # Execute the domains command
        domains_result = execute_command(ssh, domains_cmd + " 2>&1")
        sync_output += "Domain configuration:\n#{domains_result}\n" if domains_result
        
        # Enable SSL for each domain
        domain_names.each do |domain_name|
          sync_output += "\n=== Configuring SSL for #{domain_name} ===\n"
          
          # Install letsencrypt plugin if not already installed
          letsencrypt_check = execute_command(ssh, "sudo dokku plugin:list | grep letsencrypt || echo 'NOT_INSTALLED'")
          if letsencrypt_check&.include?('NOT_INSTALLED')
            sync_output += "Installing Let's Encrypt plugin...\n"
            install_result = execute_long_command(ssh, "sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git 2>&1", 300) # 5 minutes for plugin install
            sync_output += install_result if install_result
            sync_output += "\n"
          end
          
          # Configure Let's Encrypt email (using a default)
          email_cmd = "sudo dokku letsencrypt:set #{app_name} email admin@#{domain_name}"
          email_result = execute_command(ssh, email_cmd + " 2>&1")
          sync_output += "Email configuration: #{email_result}\n" if email_result
          
          # Enable SSL (this can take several minutes to request and validate certificates)
          ssl_cmd = "sudo dokku letsencrypt:enable #{app_name}"
          ssl_result = execute_long_command(ssh, ssl_cmd + " 2>&1", 300) # 5 minutes for SSL certificate generation
          sync_output += "SSL configuration: #{ssl_result}\n" if ssl_result
          
          # Check if SSL was successful
          ssl_check = execute_command(ssh, "sudo dokku letsencrypt:list | grep #{app_name} || echo 'SSL_NOT_ENABLED'")
          if ssl_check && !ssl_check.include?('SSL_NOT_ENABLED')
            sync_output += "✅ SSL enabled successfully for #{domain_name}\n"
          else
            sync_output += "⚠️ SSL configuration may have failed for #{domain_name}\n"
            sync_output += "Note: Ensure DNS A record points to #{@server.ip} and domain is accessible\n"
          end
        end
        
        # Verify final domain configuration
        verify_result = execute_command(ssh, "sudo dokku domains:report #{app_name}")
        if verify_result
          sync_output += "\n=== Final Domain Configuration ===\n"
          sync_output += verify_result
          sync_output += "\n"
        end
        
        sync_output += "\n✅ Domain configuration completed!\n"
        sync_output += "Domains are now configured with SSL certificates.\n"
        sync_output += "\n📋 Important: Ensure DNS A records point to #{@server.ip}\n"
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
    database_urls = {}
    
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
        database_urls[:database_url] = database_url
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
          database_urls[:redis_url] = redis_url
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
      database_urls: database_urls
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
end