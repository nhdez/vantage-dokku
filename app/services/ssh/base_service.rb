require "net/ssh"
require "timeout"

module Ssh
  class BaseService
    CONNECTION_TIMEOUT = 10
    COMMAND_TIMEOUT = 30
    UPDATE_TIMEOUT = 600
    INSTALL_TIMEOUT = 900
    DOMAIN_TIMEOUT = 600
    ENV_TIMEOUT = 180

    def initialize(server)
      @server = server
      @connection_details = server.connection_details
    end

    private

    def ssh_options(custom_timeout = nil)
      options = {
        port: @connection_details[:port],
        timeout: custom_timeout || CONNECTION_TIMEOUT,
        verify_host_key: :never,
        non_interactive: true
      }

      options[:auth_methods] = []

      if @connection_details[:password].present?
        options[:password] = @connection_details[:password]
        options[:auth_methods] << "password"
      end

      if @connection_details[:keys].present?
        options[:keys] = @connection_details[:keys]
        options[:auth_methods] << "publickey"
      end

      if options[:auth_methods].empty?
        raise StandardError, "No authentication method available (no SSH key or password configured)"
      end

      options
    end

    def execute_command(ssh, command)
      result = nil
      Timeout.timeout(COMMAND_TIMEOUT) do
        result = ssh.exec!(command)
      end
      result
    rescue Timeout::Error
      Rails.logger.error "Command timeout: #{command}"
      nil
    end

    def execute_long_command(ssh, command, timeout = UPDATE_TIMEOUT)
      result = nil
      Timeout.timeout(timeout) do
        result = ssh.exec!(command)
      end
      result
    rescue Timeout::Error
      Rails.logger.error "Long command timeout: #{command}"
      nil
    end

    def execute_streaming_command(ssh, command, timeout: UPDATE_TIMEOUT, &on_data)
      output = ""
      Timeout.timeout(timeout) do
        ssh.exec!(command) do |_channel, _stream, data|
          clean = sanitize_stream(data)
          output += clean
          if on_data
            clean.each_line do |line|
              stripped = line.chomp
              on_data.call(stripped) unless stripped.empty?
            end
          end
        end
      end
      output
    rescue Timeout::Error
      Rails.logger.error "Streaming command timeout: #{command}"
      output
    end

    def sanitize_stream(data)
      clean = data.to_s.force_encoding("UTF-8")
      return clean if clean.valid_encoding?
      data.to_s.encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace, replace: "?")
    end

    def shell_escape(value)
      return '""' if value.nil? || value.empty?

      if value.include?("'")
        escaped = value.gsub("\\", "\\\\").gsub('"', '\\"').gsub("$", '\\$').gsub("`", '\\`')
        "\"#{escaped}\""
      else
        "'#{value}'"
      end
    end

    def gather_server_info(ssh)
      info = {}

      begin
        os_release = execute_command(ssh, "cat /etc/os-release 2>/dev/null || cat /etc/redhat-release 2>/dev/null || uname -s")
        info[:os_version] = parse_os_version(os_release)

        cpu_info = execute_command(ssh, "cat /proc/cpuinfo | head -20")
        info[:cpu_model] = parse_cpu_model(cpu_info)
        info[:cpu_cores] = parse_cpu_cores(cpu_info)

        mem_info = execute_command(ssh, "cat /proc/meminfo | head -5")
        info[:ram_total] = parse_memory(mem_info)

        disk_info = execute_command(ssh, "df -h / | tail -1")
        info[:disk_total] = parse_disk_info(disk_info)

        uptime = execute_command(ssh, "uptime")
        info[:uptime] = uptime&.strip

        dokku_version = execute_command(ssh, "dokku version 2>/dev/null")
        info[:dokku_version] = parse_dokku_version(dokku_version)

      rescue StandardError => e
        Rails.logger.error "Failed to gather server info: #{e.message}"
      end

      info
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

    def parse_os_version(os_release)
      return "Unknown" if os_release.blank?

      if os_release.include?("PRETTY_NAME")
        match = os_release.match(/PRETTY_NAME="([^"]+)"/)
        return match[1] if match
      end

      os_release.lines.first&.strip || "Unknown"
    end

    def parse_cpu_model(cpu_info)
      return "Unknown" if cpu_info.blank?

      match = cpu_info.match(/model name\s*:\s*(.+)/)
      match ? match[1].strip : "Unknown"
    end

    def parse_cpu_cores(cpu_info)
      return nil if cpu_info.blank?

      cores = cpu_info.scan(/processor\s*:/).count
      cores > 0 ? cores : nil
    end

    def parse_memory(mem_info)
      return "Unknown" if mem_info.blank?

      match = mem_info.match(/MemTotal:\s*(\d+)\s*kB/)
      if match
        kb = match[1].to_i
        gb = (kb / 1024.0 / 1024.0).round(1)
        "#{gb} GB"
      else
        "Unknown"
      end
    end

    def parse_disk_info(disk_info)
      return "Unknown" if disk_info.blank?

      parts = disk_info.strip.split(/\s+/)
      return parts[1] if parts.length >= 2

      "Unknown"
    end

    def parse_dokku_version(dokku_output)
      return nil if dokku_output.blank?

      if dokku_output.match(/dokku version ([\d\.]+)/)
        $1
      elsif dokku_output.match(/^([\d\.]+)/)
        $1
      else
        dokku_output.strip.lines.first&.strip
      end
    end
  end
end
