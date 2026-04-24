module Ssh
  class AppService < BaseService
    def create_dokku_app(app_name)
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
            result[:output] = perform_dokku_app_creation(ssh, app_name)
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
        result[:error] = "Dokku app creation failed: #{e.message}"
      end

      result
    end

    def destroy_dokku_app(app_name)
      result = {
        success: false,
        error: nil,
        output: ""
      }

      begin
        Timeout.timeout(COMMAND_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            Rails.logger.info "Destroying Dokku app '#{app_name}' on #{@server.name}"

            check_app = execute_command(ssh, "sudo dokku apps:exists #{app_name} 2>&1")

            if check_app.nil? || check_app.include?("does not exist")
              Rails.logger.info "Dokku app '#{app_name}' does not exist on server, skipping destruction"
              result[:success] = true
              result[:output] = "App does not exist on server (already deleted or never created)"
            else
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

    def list_dokku_apps
      result = {
        success: false,
        apps: [],
        error: nil
      }

      begin
        Rails.logger.info "[SshConnectionService] Listing Dokku apps on #{@server.name}"

        Timeout.timeout(CONNECTION_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            output = execute_command(ssh, "dokku apps:list 2>&1")

            if output && !output.downcase.include?("error")
              apps = output.split("\n").select { |line| !line.include?("====>") && line.strip.present? }.map(&:strip)
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

    def get_dokku_config(app_name)
      result = {
        success: false,
        error: nil,
        config: {}
      }

      begin
        Rails.logger.info "[SshConnectionService] Getting Dokku config for app #{app_name} on #{@server.name}"

        Timeout.timeout(CONNECTION_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            config_output = execute_command(ssh, "sudo dokku config:show #{app_name} 2>&1")

            if config_output && !config_output.include?("does not exist")
              config_output.each_line do |line|
                next if line.include?("====>")

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

    def sync_dokku_ssh_keys(public_keys)
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
            result[:output] = perform_dokku_ssh_key_sync(ssh, public_keys)
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
        result[:error] = "SSH key sync failed: #{e.message}"
      end

      result
    end

    def sync_dokku_environment_variables(app_name, env_vars)
      result = {
        success: false,
        error: nil,
        output: ""
      }

      begin
        Timeout.timeout(ENV_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            result[:output] = perform_dokku_env_sync(ssh, app_name, env_vars)
            result[:success] = true

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

    private

    def perform_dokku_app_creation(ssh, app_name)
      creation_output = ""

      begin
        Rails.logger.info "Creating Dokku app '#{app_name}' on #{@server.name}"
        creation_output += "=== Creating Dokku App: #{app_name} ===\n"

        check_result = ssh.exec!("sudo dokku apps:list | grep '^#{app_name}$' || echo 'NOT_FOUND'")
        if check_result && !check_result.include?("NOT_FOUND")
          creation_output += "App '#{app_name}' already exists on this server.\n"
          return creation_output
        end

        create_result = ssh.exec!("sudo dokku apps:create #{app_name} 2>&1")
        creation_output += create_result if create_result

        verify_result = ssh.exec!("sudo dokku apps:list | grep '^#{app_name}$' || echo 'CREATION_FAILED'")
        if verify_result && !verify_result.include?("CREATION_FAILED")
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

        backup_result = ssh.exec!("sudo cp /home/dokku/.ssh/authorized_keys /home/dokku/.ssh/authorized_keys.backup.$(date +%s) 2>/dev/null || echo 'No existing keys to backup'")
        sync_output += "Backup: #{backup_result}\n" if backup_result

        ssh.exec!("sudo bash -c 'grep \"# dokku\" /home/dokku/.ssh/authorized_keys > /tmp/dokku_system_keys 2>/dev/null || echo \"# System keys\" > /tmp/dokku_system_keys'")

        ssh.exec!("sudo cp /tmp/dokku_system_keys /home/dokku/.ssh/authorized_keys")

        if public_keys.any?
          sync_output += "Adding #{public_keys.count} SSH key#{'s' unless public_keys.count == 1}...\n"

          public_keys.each_with_index do |public_key, index|
            clean_key = public_key.strip
            next if clean_key.empty?

            key_with_comment = "#{clean_key} # vantage-deployed-key-#{index + 1}"

            ssh.exec!("sudo bash -c 'echo \"#{key_with_comment}\" >> /home/dokku/.ssh/authorized_keys'")
            sync_output += "Added key #{index + 1}\n"
          end
        else
          sync_output += "No SSH keys to add. Only system keys will remain.\n"
        end

        ssh.exec!("sudo chown dokku:dokku /home/dokku/.ssh/authorized_keys")
        ssh.exec!("sudo chmod 600 /home/dokku/.ssh/authorized_keys")

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

    def perform_dokku_env_sync(ssh, app_name, env_vars)
      sync_output = ""

      begin
        Rails.logger.info "Syncing environment variables to Dokku app '#{app_name}' on #{@server.name}"
        sync_output += "=== Syncing Environment Variables to Dokku App: #{app_name} ===\n"

        app_check = ssh.exec!("sudo dokku apps:list | grep '^#{app_name}$' || echo 'APP_NOT_FOUND'")
        if app_check&.include?("APP_NOT_FOUND")
          sync_output += "⚠️ App '#{app_name}' does not exist. Creating it first...\n"
          create_result = ssh.exec!("sudo dokku apps:create #{app_name} 2>&1")
          sync_output += create_result if create_result
          sync_output += "\n"
        end

        if env_vars.any?
          sync_output += "Setting #{env_vars.count} environment variable#{'s' unless env_vars.count == 1}...\n"

          env_string = env_vars.map { |key, value| "#{key}=#{shell_escape(value)}" }.join(" ")
          config_cmd = "sudo dokku config:set #{app_name} #{env_string}"

          config_result = ssh.exec!(config_cmd + " 2>&1")
          sync_output += config_result if config_result
          sync_output += "\n"

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
  end
end
