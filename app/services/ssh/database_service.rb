module Ssh
  class DatabaseService < BaseService
    def configure_database(app_name, database_config)
      result = {
        success: false,
        error: nil,
        output: "",
        database_url: nil,
        redis_url: nil
      }

      begin
        Timeout.timeout(INSTALL_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            config_result = perform_database_configuration(ssh, app_name, database_config)
            result[:output] = config_result[:output]
            result[:database_url] = config_result[:database_url]
            result[:redis_url] = config_result[:redis_url]
            result[:success] = true

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
        output: ""
      }

      begin
        Timeout.timeout(ENV_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            result[:output] = perform_database_deletion(ssh, app_name, database_config)
            result[:success] = true

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

    private

    def perform_database_configuration(ssh, app_name, database_config)
      config_output = ""
      database_url = nil
      redis_url = nil

      begin
        Rails.logger.info "Configuring database for Dokku app '#{app_name}' on #{@server.name}"
        config_output += "=== Configuring Database for Dokku App: #{app_name} ===\n"

        app_check = execute_command(ssh, "sudo dokku apps:list | grep '^#{app_name}$' || echo 'APP_NOT_FOUND'")
        if app_check&.include?("APP_NOT_FOUND")
          config_output += "⚠️ App '#{app_name}' does not exist. Creating it first...\n"
          create_result = execute_command(ssh, "sudo dokku apps:create #{app_name} 2>&1")
          config_output += create_result if create_result
          config_output += "\n"
        end

        db_type = database_config.database_type
        plugin_url = database_config.plugin_url

        config_output += "\n=== Installing #{database_config.display_name} Plugin ===\n"
        plugin_check = execute_command(ssh, "sudo dokku plugin:list | grep #{db_type} || echo 'NOT_INSTALLED'")

        if plugin_check&.include?("NOT_INSTALLED")
          config_output += "Installing #{database_config.display_name} plugin...\n"
          install_result = execute_long_command(ssh, "sudo dokku plugin:install #{plugin_url} 2>&1", 300)
          config_output += install_result if install_result
          config_output += "\n"
        else
          config_output += "#{database_config.display_name} plugin already installed.\n"
        end

        db_name = database_config.database_name
        config_output += "\n=== Creating #{database_config.display_name} Database: #{db_name} ===\n"

        db_check = execute_command(ssh, "sudo dokku #{db_type}:list | grep '^#{db_name}$' || echo 'NOT_FOUND'")
        if db_check&.include?("NOT_FOUND")
          config_output += "Creating database '#{db_name}'...\n"
          create_db_result = execute_long_command(ssh, "sudo dokku #{db_type}:create #{db_name} 2>&1", 300)
          config_output += create_db_result if create_db_result
          config_output += "\n"
        else
          config_output += "Database '#{db_name}' already exists.\n"
        end

        config_output += "=== Linking Database to App ===\n"
        link_result = execute_command(ssh, "sudo dokku #{db_type}:link #{db_name} #{app_name} 2>&1")
        config_output += link_result if link_result
        config_output += "\n"

        config_output += "=== Setting Database Environment Variable ===\n"
        db_url_result = execute_command(ssh, "sudo dokku #{db_type}:info #{db_name} --dsn 2>&1")
        if db_url_result && !db_url_result.include?("ERROR") && !db_url_result.strip.empty?
          database_url = db_url_result.strip
          config_output += "Retrieved database URL: #{database_url[0..20]}...\n"

          set_env_result = execute_command(ssh, "sudo dokku config:set #{app_name} DATABASE_URL='#{database_url}' 2>&1")
          config_output += set_env_result if set_env_result
          config_output += "DATABASE_URL environment variable set successfully.\n"
        else
          config_output += "Warning: Could not retrieve database URL automatically. Link command should have set it.\n"
        end
        config_output += "\n"

        if database_config.redis_enabled?
          redis_name = database_config.redis_name
          config_output += "\n=== Installing Redis Plugin ===\n"

          redis_plugin_check = execute_command(ssh, "sudo dokku plugin:list | grep redis || echo 'NOT_INSTALLED'")
          if redis_plugin_check&.include?("NOT_INSTALLED")
            config_output += "Installing Redis plugin...\n"
            redis_install_result = execute_long_command(ssh, "sudo dokku plugin:install #{database_config.redis_plugin_url} 2>&1", 300)
            config_output += redis_install_result if redis_install_result
            config_output += "\n"
          else
            config_output += "Redis plugin already installed.\n"
          end

          config_output += "=== Creating Redis Instance: #{redis_name} ===\n"
          redis_check = execute_command(ssh, "sudo dokku redis:list | grep '^#{redis_name}$' || echo 'NOT_FOUND'")
          if redis_check&.include?("NOT_FOUND")
            config_output += "Creating Redis instance '#{redis_name}'...\n"
            create_redis_result = execute_long_command(ssh, "sudo dokku redis:create #{redis_name} 2>&1", 180)
            config_output += create_redis_result if create_redis_result
            config_output += "\n"
          else
            config_output += "Redis instance '#{redis_name}' already exists.\n"
          end

          config_output += "=== Linking Redis to App ===\n"
          redis_link_result = execute_command(ssh, "sudo dokku redis:link #{redis_name} #{app_name} 2>&1")
          config_output += redis_link_result if redis_link_result
          config_output += "\n"

          config_output += "=== Setting Redis Environment Variable ===\n"
          redis_url_result = execute_command(ssh, "sudo dokku redis:info #{redis_name} --dsn 2>&1")
          if redis_url_result && !redis_url_result.include?("ERROR") && !redis_url_result.strip.empty?
            redis_url = redis_url_result.strip
            config_output += "Retrieved Redis URL: #{redis_url[0..20]}...\n"

            set_redis_env_result = execute_command(ssh, "sudo dokku config:set #{app_name} REDIS_URL='#{redis_url}' 2>&1")
            config_output += set_redis_env_result if set_redis_env_result
            config_output += "REDIS_URL environment variable set successfully.\n"
          else
            config_output += "Warning: Could not retrieve Redis URL automatically. Link command should have set it.\n"
          end
          config_output += "\n"
        end

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

        deletion_output += "\n=== Removing Environment Variables ===\n"

        env_var_name = database_config.environment_variable_name
        if env_var_name
          deletion_output += "Removing #{env_var_name} environment variable...\n"
          unset_result = execute_command(ssh, "sudo dokku config:unset #{app_name} #{env_var_name} 2>&1")
          deletion_output += unset_result if unset_result
        end

        if database_config.redis_enabled?
          redis_env_var = database_config.redis_environment_variable_name
          if redis_env_var
            deletion_output += "Removing #{redis_env_var} environment variable...\n"
            unset_redis_result = execute_command(ssh, "sudo dokku config:unset #{app_name} #{redis_env_var} 2>&1")
            deletion_output += unset_redis_result if unset_redis_result
          end
        end
        deletion_output += "\n"

        if database_config.redis_enabled?
          redis_name = database_config.redis_name
          deletion_output += "=== Detaching and Deleting Redis Instance: #{redis_name} ===\n"

          deletion_output += "Unlinking Redis from app...\n"
          redis_unlink_result = execute_command(ssh, "sudo dokku redis:unlink #{redis_name} #{app_name} 2>&1")
          deletion_output += redis_unlink_result if redis_unlink_result

          deletion_output += "Deleting Redis instance...\n"
          redis_delete_result = execute_command(ssh, "sudo dokku redis:destroy #{redis_name} --force 2>&1")
          deletion_output += redis_delete_result if redis_delete_result
          deletion_output += "\n"
        end

        deletion_output += "=== Detaching and Deleting #{database_config.display_name} Database: #{db_name} ===\n"

        deletion_output += "Unlinking database from app...\n"
        unlink_result = execute_command(ssh, "sudo dokku #{db_type}:unlink #{db_name} #{app_name} 2>&1")
        deletion_output += unlink_result if unlink_result

        deletion_output += "Deleting database...\n"
        delete_result = execute_command(ssh, "sudo dokku #{db_type}:destroy #{db_name} --force 2>&1")
        deletion_output += delete_result if delete_result
        deletion_output += "\n"

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
  end
end
