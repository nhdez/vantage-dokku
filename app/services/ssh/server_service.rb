module Ssh
  class ServerService < BaseService
    def install_dokku_with_key_setup
      result = {
        success: false,
        error: nil,
        output: "",
        dokku_installed: false
      }

      begin
        Timeout.timeout(INSTALL_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            result[:output] = perform_dokku_installation(ssh)
            result[:success] = true
            result[:dokku_installed] = true

            gather_server_info_after_install(ssh)

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

    def update_server_packages(&on_data)
      result = {
        success: false,
        error: nil,
        output: "",
        packages_updated: 0
      }

      begin
        Timeout.timeout(UPDATE_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            result[:output] = perform_system_update(ssh, &on_data)
            result[:success] = true

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
        output: ""
      }

      begin
        Timeout.timeout(CONNECTION_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            result[:output] = perform_server_restart(ssh)
            result[:success] = true

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

    def test_connection_and_gather_info
      result = {
        success: false,
        error: nil,
        server_info: {}
      }

      begin
        Timeout.timeout(CONNECTION_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            result[:success] = true
            result[:server_info] = gather_server_info(ssh)

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

      if result[:success]
        @server.update!(
          connection_status: "connected",
          last_connected_at: Time.current
        )
      else
        @server.update!(connection_status: "failed")
      end

      result
    end

    private

    def perform_dokku_installation(ssh)
      installation_output = ""
      dokku_version = AppSetting.dokku_install_version

      begin
        installation_output += "=== Setting up SSH key ===\n"
        setup_output = setup_ssh_key(ssh)
        installation_output += setup_output
        installation_output += "\n"

        installation_output += "=== Checking for existing Dokku installation ===\n"
        dokku_check = ssh.exec!("command -v dokku >/dev/null 2>&1 && echo 'DOKKU_EXISTS' || echo 'DOKKU_NOT_FOUND'")
        installation_output += dokku_check if dokku_check

        if dokku_check&.include?("DOKKU_EXISTS")
          installation_output += "Dokku is already installed on this server.\n"
          installation_output += "Checking version...\n"
          version_output = ssh.exec!("dokku version 2>/dev/null")
          installation_output += version_output if version_output
          return installation_output
        end

        installation_output += "\n=== Downloading Dokku v#{dokku_version} bootstrap script ===\n"
        download_cmd = "wget -NP . https://dokku.com/install/v#{dokku_version}/bootstrap.sh"
        download_output = execute_long_command(ssh, download_cmd, 120)
        installation_output += download_output if download_output
        installation_output += "\n"

        installation_output += "=== Installing Dokku v#{dokku_version} ===\n"
        installation_output += "This may take several minutes...\n"

        install_cmd = "sudo DOKKU_TAG=v#{dokku_version} bash bootstrap.sh"
        install_output = execute_long_command(ssh, install_cmd, 720)
        installation_output += install_output if install_output
        installation_output += "\n"

        installation_output += "=== Verifying Dokku installation ===\n"
        verify_output = execute_command(ssh, "dokku version 2>/dev/null")
        if verify_output
          installation_output += verify_output
          installation_output += "\n✅ Dokku installation completed successfully!\n"
        else
          installation_output += "⚠️ Dokku installation may have failed. Please check the logs above.\n"
        end

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

      return "⚠️ No public key configured in environment variables.\n" unless ENV["DOKKU_SSH_PUBLIC_KEY"].present?

      public_key = ENV["DOKKU_SSH_PUBLIC_KEY"].strip

      ssh.exec!("mkdir -p ~/.ssh")
      ssh.exec!("chmod 700 ~/.ssh")

      add_key_cmd = "echo '#{public_key}' >> ~/.ssh/authorized_keys"
      setup_output += ssh.exec!(add_key_cmd) || ""

      ssh.exec!("chmod 600 ~/.ssh/authorized_keys")
      ssh.exec!("chown -R $USER:$USER ~/.ssh")

      setup_output += "✅ SSH public key added to authorized_keys\n"
      setup_output
    end

    def setup_initial_dokku_config(ssh)
      config_output = ""

      if ENV["DOKKU_SSH_PUBLIC_KEY"].present?
        public_key = ENV["DOKKU_SSH_PUBLIC_KEY"].strip

        add_key_to_dokku = "echo '#{public_key}' | sudo dokku ssh-keys:add admin"
        config_output += ssh.exec!(add_key_to_dokku) || ""
        config_output += "✅ SSH key added to Dokku for admin user\n"
      end

      if ENV["DOKKU_LETSENCRYPT_EMAIL"].present?
        email = ENV["DOKKU_LETSENCRYPT_EMAIL"].strip
        config_output += "\n=== Configuring Let's Encrypt Global Email ===\n"

        config_output += "Installing Let's Encrypt plugin...\n"
        install_plugin = ssh.exec!("sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git 2>&1 || echo 'Plugin already installed'")
        config_output += install_plugin || ""

        set_email_cmd = "sudo dokku letsencrypt:set --global email #{email}"
        email_output = ssh.exec!(set_email_cmd)
        config_output += email_output || ""
        config_output += "\n✅ Let's Encrypt global email set to: #{email}\n"
      else
        config_output += "\n⚠️ DOKKU_LETSENCRYPT_EMAIL not configured - SSL certificates will require manual email setup\n"
      end

      config_output += "\n✅ Initial Dokku configuration completed\n"
      config_output += "\nNext steps:\n"
      config_output += "- Access Dokku at: http://#{@server.ip}\n"
      config_output += "- Use 'dokku apps:create myapp' to create your first app\n"
      config_output += "- Configure domains with 'dokku domains:set myapp yourdomain.com'\n"

      config_output
    end

    def gather_server_info_after_install(ssh)
      info = {}

      begin
        dokku_version = execute_command(ssh, "dokku version 2>/dev/null")
        info[:dokku_version] = parse_dokku_version(dokku_version)

        @server.update!(dokku_version: info[:dokku_version]) if info[:dokku_version]

      rescue StandardError => e
        Rails.logger.error "Failed to gather server info after Dokku install: #{e.message}"
      end
    end

    def perform_system_update(ssh, &on_data)
      update_output = ""
      emit = ->(msg) { on_data.call(msg) if on_data }

      begin
        Rails.logger.info "Running apt update on #{@server.name}"
        emit.call("=== Running apt update ===")
        update_output += "=== Running apt update ===\n"

        apt_update_result = on_data ?
          execute_streaming_command(ssh, "sudo apt update 2>&1", timeout: 120, &on_data) :
          execute_long_command(ssh, "sudo apt update 2>&1", 120)
        update_output += apt_update_result.to_s + "\n"

        Rails.logger.info "Running apt upgrade on #{@server.name}"
        emit.call("=== Running apt upgrade ===")
        update_output += "=== Running apt upgrade ===\n"

        apt_upgrade_result = on_data ?
          execute_streaming_command(ssh, "sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y 2>&1", timeout: 480, &on_data) :
          execute_long_command(ssh, "sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y 2>&1", 480)
        update_output += apt_upgrade_result.to_s + "\n"

        reboot_check = execute_command(ssh, "[ -f /var/run/reboot-required ] && echo 'REBOOT_REQUIRED' || echo 'NO_REBOOT'")
        if reboot_check&.include?("REBOOT_REQUIRED")
          update_output += "=== NOTICE ===\nA system reboot is required to complete some updates.\n"
          emit.call("=== REBOOT REQUIRED ===")
        end

        Rails.logger.info "System update completed successfully on #{@server.name}"

      rescue StandardError => e
        Rails.logger.error "System update failed on #{@server.name}: #{e.message}"
        update_output += "\n=== ERROR ===\n#{e.message}\n"
        emit.call("ERROR: #{e.message}")
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

        restart_result = ssh.exec!("sudo shutdown -r now 2>&1")
        restart_output += restart_result if restart_result

        restart_output += "✅ Restart command executed successfully.\n"
        restart_output += "The server is now rebooting and will be unavailable until the restart completes.\n"

        Rails.logger.info "Server restart command executed successfully on #{@server.name}"

      rescue StandardError => e
        Rails.logger.error "Server restart failed on #{@server.name}: #{e.message}"
        restart_output += "\n=== ERROR ===\n"
        restart_output += "Restart process encountered an error: #{e.message}\n"
        # Don't re-raise — disconnection is expected during restart
      end

      restart_output
    end
  end
end
