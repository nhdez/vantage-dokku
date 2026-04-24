module Ssh
  class DomainService < BaseService
    def debug_dokku_domains(app_name)
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
            debug_output = "=== Dokku Domain Debug for #{app_name} ===\n\n"

            app_check = execute_command(ssh, "sudo dokku apps:list | grep #{app_name} || echo 'NOT_FOUND'")
            debug_output += "App exists: #{!app_check&.include?('NOT_FOUND')}\n\n"

            debug_output += "=== Domain Configuration ===\n"
            domains = execute_command(ssh, "sudo dokku domains:report #{app_name} 2>&1")
            debug_output += domains if domains
            debug_output += "\n"

            debug_output += "=== Nginx Configuration ===\n"
            nginx_conf = execute_command(ssh, "sudo cat /home/dokku/#{app_name}/nginx.conf 2>&1 | head -50")
            debug_output += nginx_conf if nginx_conf
            debug_output += "\n"

            debug_output += "=== Let's Encrypt Status ===\n"
            ssl_status = execute_command(ssh, "sudo dokku letsencrypt:list | grep #{app_name} || echo 'NO_SSL'")
            debug_output += ssl_status if ssl_status
            debug_output += "\n"

            debug_output += "=== Certificate Details ===\n"
            cert_info = execute_command(ssh, "sudo dokku letsencrypt:info #{app_name} 2>&1")
            debug_output += cert_info if cert_info
            debug_output += "\n"

            debug_output += "=== Proxy Ports ===\n"
            ports = execute_command(ssh, "sudo dokku proxy:ports #{app_name} 2>&1")
            debug_output += ports if ports
            debug_output += "\n"

            debug_output += "=== All Apps on Server ===\n"
            all_apps = execute_command(ssh, "sudo dokku apps:list 2>&1")
            debug_output += all_apps if all_apps
            debug_output += "\n"

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

    def remove_domain_from_app(app_name, domain_to_remove)
      result = {
        success: false,
        error: nil,
        output: ""
      }

      begin
        Timeout.timeout(DOMAIN_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            removal_output = "=== Removing Domain #{domain_to_remove} from App #{app_name} ===\n\n"

            app_check = execute_command(ssh, "sudo dokku apps:list | grep '^#{app_name}$' || echo 'APP_NOT_FOUND'")
            if app_check&.include?("APP_NOT_FOUND")
              removal_output += "App '#{app_name}' does not exist.\n"
              result[:success] = true
              result[:output] = removal_output
              return result
            end

            removal_output += "Getting current domains...\n"
            current_domains_cmd = "sudo dokku domains:report #{app_name} --domains-app-vhosts 2>/dev/null"
            current_domains_result = execute_command(ssh, current_domains_cmd)

            if current_domains_result
              current_domains = current_domains_result.split.reject { |d| d.empty? }
              removal_output += "Current domains: #{current_domains.join(', ')}\n"

              remaining_domains = current_domains - [ domain_to_remove ]

              if remaining_domains.empty?
                removal_output += "\n=== No domains remaining, clearing all domains and SSL ===\n"

                removal_output += "Disabling SSL...\n"
                disable_ssl = execute_command(ssh, "sudo dokku letsencrypt:disable #{app_name} 2>&1")
                removal_output += disable_ssl if disable_ssl

                removal_output += "Clearing all domains...\n"
                clear_cmd = "sudo dokku domains:clear #{app_name} 2>&1"
                clear_result = execute_command(ssh, clear_cmd)
                removal_output += clear_result if clear_result

                removal_output += "\nApp will now use default Dokku domain.\n"
              else
                removal_output += "\n=== Updating domains to remove #{domain_to_remove} ===\n"

                removal_output += "Temporarily disabling SSL...\n"
                execute_command(ssh, "sudo dokku letsencrypt:disable #{app_name} 2>&1")

                domains_string = remaining_domains.join(" ")
                set_cmd = "sudo dokku domains:set #{app_name} #{domains_string} 2>&1"
                removal_output += "Setting domains to: #{domains_string}\n"
                set_result = execute_command(ssh, set_cmd)
                removal_output += set_result if set_result

                ps_check = execute_command(ssh, "sudo dokku ps:report #{app_name} --ps-running 2>&1")
                if ps_check && ps_check.include?("true")
                  removal_output += "\n=== Re-enabling SSL for remaining domains ===\n"

                  execute_command(ssh, "sudo dokku letsencrypt:set #{app_name} server 2>&1")

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
        output: ""
      }

      begin
        Timeout.timeout(DOMAIN_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            result[:output] = perform_dokku_domain_sync(ssh, app_name, domain_names)
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
        result[:error] = "Domain sync failed: #{e.message}"
      end

      result
    end

    private

    def perform_dokku_domain_sync(ssh, app_name, domain_names)
      sync_output = ""

      begin
        Rails.logger.info "Syncing domains to Dokku app '#{app_name}' on #{@server.name}"
        sync_output += "=== Syncing Domains to Dokku App: #{app_name} ===\n"

        app_check = execute_command(ssh, "sudo dokku apps:list | grep '^#{app_name}$' || echo 'APP_NOT_FOUND'")
        if app_check&.include?("APP_NOT_FOUND")
          sync_output += "⚠️ App '#{app_name}' does not exist. Creating it first...\n"
          create_result = execute_command(ssh, "sudo dokku apps:create #{app_name} 2>&1")
          sync_output += create_result if create_result
          sync_output += "\n"
        end

        if domain_names.any?
          sync_output += "Setting #{domain_names.count} domain#{'s' unless domain_names.count == 1}...\n"

          clear_cmd = "sudo dokku domains:clear #{app_name}"
          execute_command(ssh, clear_cmd + " 2>&1")
          sync_output += "Clearing existing domains...\n"

          domains_string = domain_names.join(" ")
          domains_cmd = "sudo dokku domains:set #{app_name} #{domains_string}"

          domains_result = execute_command(ssh, domains_cmd + " 2>&1")
          sync_output += "Domain configuration:\n#{domains_result}\n" if domains_result

          sync_output += "\n=== Configuring SSL for all domains ===\n"

          letsencrypt_check = execute_command(ssh, "sudo dokku plugin:list | grep letsencrypt || echo 'NOT_INSTALLED'")
          if letsencrypt_check&.include?("NOT_INSTALLED")
            sync_output += "Installing Let's Encrypt plugin...\n"
            install_result = execute_long_command(ssh, "sudo dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git 2>&1", 300)
            sync_output += install_result if install_result
            sync_output += "\n"
          end

          sync_output += "Cleaning up any existing SSL configuration...\n"
          execute_command(ssh, "sudo dokku letsencrypt:disable #{app_name} 2>&1")

          letsencrypt_email = ENV["DOKKU_LETSENCRYPT_EMAIL"]

          if letsencrypt_email.present?
            sync_output += "Setting Let's Encrypt email to: #{letsencrypt_email}\n"
            email_cmd = "sudo dokku letsencrypt:set #{app_name} email #{letsencrypt_email}"
            email_result = execute_command(ssh, email_cmd + " 2>&1")
            sync_output += email_result if email_result && email_result.include?("Setting")
          else
            sync_output += "⚠️ Warning: DOKKU_LETSENCRYPT_EMAIL not configured\n"
            sync_output += "Using server's global Let's Encrypt email configuration\n"
          end

          execute_command(ssh, "sudo dokku letsencrypt:set #{app_name} server 2>&1")

          auto_renew_result = execute_command(ssh, "sudo dokku letsencrypt:set #{app_name} auto-renew true 2>&1")
          sync_output += "Enabling auto-renewal...\n"

          sync_output += "\nRequesting SSL certificates for all domains...\n"
          sync_output += "This may take a few minutes while Let's Encrypt validates the domains...\n"
          ssl_cmd = "sudo dokku letsencrypt:enable #{app_name}"
          ssl_result = execute_long_command(ssh, ssl_cmd + " 2>&1", 300)

          if ssl_result
            sync_output += "SSL Result:\n#{ssl_result}\n"

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

          verify_result = execute_command(ssh, "sudo dokku domains:report #{app_name}")
          if verify_result
            sync_output += "\n=== Final Domain Configuration ===\n"
            sync_output += verify_result
            sync_output += "\n"
          end

          ssl_status = execute_command(ssh, "sudo dokku letsencrypt:list | grep #{app_name} || echo 'NO_SSL'")
          if ssl_status && !ssl_status.include?("NO_SSL")
            sync_output += "=== SSL Status ===\n"
            sync_output += ssl_status
            sync_output += "\n"
          end

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
  end
end
