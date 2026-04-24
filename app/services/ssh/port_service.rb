module Ssh
  class PortService < BaseService
    def list_ports(app_name)
      result = {
        success: false,
        error: nil,
        ports: []
      }

      begin
        Rails.logger.info "[SshConnectionService] Listing port mappings for app #{app_name} on #{@server.name}"

        Timeout.timeout(CONNECTION_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            ports_output = execute_command(ssh, "sudo dokku ports:list #{app_name} 2>&1")

            if ports_output && !ports_output.include?("does not exist") && !ports_output.include?("No port mappings")
              ports_output.each_line do |line|
                next if line.include?("------>") || line.strip.empty?

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
            elsif ports_output&.include?("No port mappings")
              Rails.logger.info "[SshConnectionService] No port mappings configured for #{app_name}"
              result[:success] = true
            else
              result[:error] = "App does not exist or error retrieving ports"
              Rails.logger.warn "[SshConnectionService] #{result[:error]}: #{ports_output&.first(200)}"
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
        result[:error] = "Failed to list ports: #{e.message}"
        Rails.logger.error "[SshConnectionService] #{result[:error]}"
        Rails.logger.error e.backtrace.join("\n")
      end

      result
    end

    def add_port(app_name, scheme, host_port, container_port)
      result = {
        success: false,
        error: nil
      }

      begin
        Rails.logger.info "[SshConnectionService] Adding port mapping #{scheme}:#{host_port}:#{container_port} to app #{app_name}"

        Timeout.timeout(CONNECTION_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            port_string = "#{scheme}:#{host_port}:#{container_port}"
            output = execute_command(ssh, "sudo dokku ports:add #{app_name} #{port_string} 2>&1")

            if output && !output.include?("does not exist") && !output.downcase.include?("error")
              Rails.logger.info "[SshConnectionService] Successfully added port mapping"
              result[:success] = true
            else
              result[:error] = output || "Failed to add port mapping"
              Rails.logger.error "[SshConnectionService] #{result[:error]}"
            end

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

    def remove_port(app_name, scheme, host_port, container_port)
      result = {
        success: false,
        error: nil
      }

      begin
        Rails.logger.info "[SshConnectionService] Removing port mapping #{scheme}:#{host_port}:#{container_port} from app #{app_name}"

        Timeout.timeout(CONNECTION_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            port_string = "#{scheme}:#{host_port}:#{container_port}"
            output = execute_command(ssh, "sudo dokku ports:remove #{app_name} #{port_string} 2>&1")

            if output && !output.include?("does not exist") && !output.downcase.include?("error")
              Rails.logger.info "[SshConnectionService] Successfully removed port mapping"
              result[:success] = true
            else
              result[:error] = output || "Failed to remove port mapping"
              Rails.logger.error "[SshConnectionService] #{result[:error]}"
            end

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

    def clear_ports(app_name)
      result = {
        success: false,
        error: nil
      }

      begin
        Rails.logger.info "[SshConnectionService] Clearing all port mappings for app #{app_name}"

        Timeout.timeout(CONNECTION_TIMEOUT) do
          Net::SSH.start(
            @connection_details[:host],
            @connection_details[:username],
            ssh_options
          ) do |ssh|
            output = execute_command(ssh, "sudo dokku ports:clear #{app_name} 2>&1")

            if output && !output.include?("does not exist") && !output.downcase.include?("error")
              Rails.logger.info "[SshConnectionService] Successfully cleared all port mappings"
              result[:success] = true
            else
              result[:error] = output || "Failed to clear port mappings"
              Rails.logger.error "[SshConnectionService] #{result[:error]}"
            end

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
  end
end
