module Ssh
  class FirewallService < BaseService
    def check_ufw_status
      result = {
        success: false,
        error: nil,
        enabled: false,
        status: nil
      }

      begin
        Rails.logger.info "[SshConnectionService] Checking UFW status on #{@server.name}"

        Timeout.timeout(COMMAND_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            status_output = execute_command(ssh, "sudo ufw status 2>&1")

            if status_output
              result[:status] = status_output
              result[:enabled] = status_output.include?("Status: active")
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

    def configure_ufw_for_docker
      result = {
        success: false,
        error: nil
      }

      begin
        Rails.logger.info "[SshConnectionService] Configuring UFW for Docker compatibility on #{@server.name}"

        Timeout.timeout(COMMAND_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            check_output = execute_command(ssh, "sudo grep -q 'DOCKER-USER' /etc/ufw/after.rules && echo 'exists' || echo 'not_exists'")

            if check_output&.strip == "not_exists"
              Rails.logger.info "[SshConnectionService] Adding Docker compatibility rules to UFW"

              execute_command(ssh, "sudo cp /etc/ufw/after.rules /etc/ufw/after.rules.bak")

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

              execute_command(ssh, configure_cmd)

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

    def enable_ufw
      result = {
        success: false,
        error: nil,
        warnings: []
      }

      begin
        Rails.logger.info "[SshConnectionService] Enabling UFW on #{@server.name}"

        Timeout.timeout(COMMAND_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            Rails.logger.info "[SshConnectionService] Step 1: Configuring UFW for Docker"
            docker_config_result = configure_ufw_for_docker
            unless docker_config_result[:success]
              result[:warnings] << "Failed to configure Docker compatibility: #{docker_config_result[:error]}"
            end

            Rails.logger.info "[SshConnectionService] Step 2: Adding essential rules"

            execute_command(ssh, "sudo ufw allow 22/tcp comment 'SSH' 2>&1")
            execute_command(ssh, "sudo ufw allow 80/tcp comment 'HTTP' 2>&1")
            execute_command(ssh, "sudo ufw allow 443/tcp comment 'HTTPS' 2>&1")

            Rails.logger.info "[SshConnectionService] Step 3: Enabling UFW"
            output = execute_command(ssh, "sudo ufw --force enable 2>&1")

            if output && !output.downcase.include?("error")
              Rails.logger.info "[SshConnectionService] Step 4: Restarting Docker"
              restart_output = execute_command(ssh, "sudo systemctl restart docker 2>&1")

              if restart_output && restart_output.downcase.include?("error")
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

    def disable_ufw
      result = {
        success: false,
        error: nil
      }

      begin
        Rails.logger.info "[SshConnectionService] Disabling UFW on #{@server.name}"

        Timeout.timeout(COMMAND_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            output = execute_command(ssh, "sudo ufw disable 2>&1")

            if output && !output.downcase.include?("error")
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

    def list_ufw_rules
      result = {
        success: false,
        error: nil,
        rules: []
      }

      begin
        Rails.logger.info "[SshConnectionService] Listing UFW rules on #{@server.name}"

        Timeout.timeout(COMMAND_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            output = execute_command(ssh, "sudo ufw status numbered 2>&1")

            if output && !output.downcase.include?("error")
              output.each_line do |line|
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

    def add_ufw_rule(rule_command)
      result = {
        success: false,
        error: nil
      }

      begin
        Rails.logger.info "[SshConnectionService] Adding UFW rule on #{@server.name}: #{rule_command}"

        Timeout.timeout(COMMAND_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            output = execute_command(ssh, "sudo #{rule_command} 2>&1")

            if output && !output.downcase.include?("error") && !output.downcase.include?("could not")
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

    def delete_ufw_rule(rule_number)
      result = {
        success: false,
        error: nil
      }

      begin
        Rails.logger.info "[SshConnectionService] Deleting UFW rule ##{rule_number} on #{@server.name}"

        Timeout.timeout(COMMAND_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            output = execute_command(ssh, "yes | sudo ufw delete #{rule_number} 2>&1")

            if output && !output.downcase.include?("error")
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

    def reset_ufw
      result = {
        success: false,
        error: nil
      }

      begin
        Rails.logger.info "[SshConnectionService] Resetting UFW on #{@server.name}"

        Timeout.timeout(COMMAND_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            output = execute_command(ssh, "yes | sudo ufw --force reset 2>&1")

            if output && !output.downcase.include?("error")
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
  end
end
