require "open3"
require "timeout"

# Executes Kamal CLI commands as subprocesses, streaming output line-by-line
# via ActionCable.  Kamal itself handles SSH to the target servers — Vantage
# only needs network access to the Docker registry and the servers' SSH port.
#
# Usage:
#   service = KamalCommandService.new(kamal_configuration,
#               broadcast_channel: "kamal_deployment_logs_#{uuid}")
#   result = service.deploy
#   # => { success: true, output: [...], error: nil }
class KamalCommandService
  # Reuse the timeout constants defined in SshConnectionService
  COMMAND_TIMEOUT = 30
  UPDATE_TIMEOUT  = 600
  INSTALL_TIMEOUT = 900

  def initialize(kamal_configuration, broadcast_channel: nil)
    @config    = kamal_configuration
    @channel   = broadcast_channel
    @generator = KamalConfigGenerator.new(kamal_configuration)
  end

  # ─── Deployment operations ──────────────────────────────────────────────────

  def deploy
    run_kamal("deploy", timeout: UPDATE_TIMEOUT)
  end

  def rollback(version)
    run_kamal("rollback #{version}", timeout: UPDATE_TIMEOUT)
  end

  def setup
    run_kamal("setup", timeout: INSTALL_TIMEOUT)
  end

  # ─── App lifecycle ──────────────────────────────────────────────────────────

  def restart
    run_kamal("app restart", timeout: COMMAND_TIMEOUT)
  end

  def stop
    run_kamal("app stop", timeout: COMMAND_TIMEOUT)
  end

  def start
    run_kamal("app start", timeout: COMMAND_TIMEOUT)
  end

  def app_details
    run_kamal("app details", timeout: COMMAND_TIMEOUT)
  end

  def app_logs(since: "5m")
    run_kamal("app logs --since #{since}", timeout: COMMAND_TIMEOUT)
  end

  def app_exec(command)
    # Shell-escape the command to prevent injection
    safe_cmd = Shellwords.escape(command)
    run_kamal("app exec #{safe_cmd}", timeout: UPDATE_TIMEOUT)
  end

  # ─── Environment ────────────────────────────────────────────────────────────

  def env_push
    run_kamal("env push", timeout: COMMAND_TIMEOUT)
  end

  # ─── Accessories ────────────────────────────────────────────────────────────

  def accessory_boot(name)
    run_kamal("accessory boot #{Shellwords.escape(name)}", timeout: UPDATE_TIMEOUT)
  end

  def accessory_reboot(name)
    run_kamal("accessory reboot #{Shellwords.escape(name)}", timeout: UPDATE_TIMEOUT)
  end

  def accessory_remove(name)
    run_kamal("accessory remove #{Shellwords.escape(name)}", timeout: UPDATE_TIMEOUT)
  end

  def accessory_exec(name, command)
    run_kamal(
      "accessory exec #{Shellwords.escape(name)} #{Shellwords.escape(command)}",
      timeout: UPDATE_TIMEOUT
    )
  end

  def accessory_details(name)
    run_kamal("accessory details #{Shellwords.escape(name)}", timeout: COMMAND_TIMEOUT)
  end

  # ─── Proxy ──────────────────────────────────────────────────────────────────

  def proxy_reboot
    run_kamal("proxy reboot", timeout: UPDATE_TIMEOUT)
  end

  def proxy_details
    run_kamal("proxy details", timeout: COMMAND_TIMEOUT)
  end

  private

  # ─── Core execution ─────────────────────────────────────────────────────────

  def run_kamal(subcommand, timeout:)
    result = { success: false, output: [], error: nil }

    unless @generator.valid_for_generation?
      result[:error] = "Kamal configuration is incomplete: #{@generator.missing_fields.join(', ')}"
      broadcast_line("[ERROR] #{result[:error]}")
      return result
    end

    @generator.write_config_files!
    config_path = @generator.config_dir_path.join("deploy.yml").to_s

    cmd = [ kamal_bin, subcommand.split, "-c", config_path ].flatten

    Rails.logger.info "[KamalCommandService] Running: #{cmd.join(' ')}"

    begin
      Timeout.timeout(timeout) do
        Open3.popen3(*cmd) do |_stdin, stdout, stderr, wait_thr|
          # Stream stdout and stderr concurrently using threads so neither
          # blocks the other.
          stdout_thread = Thread.new do
            stdout.each_line { |line| handle_line(line.chomp, result) }
          end
          stderr_thread = Thread.new do
            stderr.each_line { |line| handle_line(line.chomp, result) }
          end

          stdout_thread.join
          stderr_thread.join

          result[:success] = wait_thr.value.success?
        end
      end
    rescue Timeout::Error
      result[:error] = "Kamal command timed out after #{timeout}s"
      broadcast_line("[ERROR] #{result[:error]}")
      Rails.logger.error "[KamalCommandService] Timeout running: #{subcommand}"
    rescue Errno::ENOENT
      result[:error] = "Kamal binary not found. Ensure the kamal gem is installed."
      broadcast_line("[ERROR] #{result[:error]}")
      Rails.logger.error "[KamalCommandService] #{result[:error]}"
    rescue StandardError => e
      result[:error] = "Command failed: #{e.message}"
      broadcast_line("[ERROR] #{result[:error]}")
      Rails.logger.error "[KamalCommandService] #{result[:error]}"
    ensure
      @generator.cleanup!
    end

    result
  end

  def handle_line(line, result)
    clean = sanitize_utf8(line)
    result[:output] << clean
    broadcast_line(clean)
    Rails.logger.debug "[KamalCommandService] #{clean}"
  end

  def broadcast_line(message)
    return unless @channel.present?

    ActionCable.server.broadcast(@channel, {
      type: "data",
      message: message,
      timestamp: Time.current.iso8601
    })
  end

  def sanitize_utf8(text)
    return "" if text.nil?

    clean = text.force_encoding("UTF-8")
    return clean if clean.valid_encoding?

    text.encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace, replace: "?")
  end

  def kamal_bin
    Gem.bin_path("kamal", "kamal")
  rescue Gem::GemNotFoundException
    # Fall back to PATH lookup if gem isn't in the bundle
    "kamal"
  end
end
