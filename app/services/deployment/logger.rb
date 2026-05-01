class Deployment::Logger
  attr_reader :entries

  def initialize(deployment, attempt)
    @deployment = deployment
    @attempt = attempt
    @entries = []
  end

  def log(message)
    clean = sanitize(message.to_s)
    line = "[#{Time.current.strftime('%H:%M:%S')}] #{clean}"
    @entries << line
    Rails.logger.info "[DeploymentService] [#{@deployment.uuid}] [Attempt ##{@attempt.attempt_number}] #{clean}"
    @attempt.update_column(:logs, safe_entries.join("\n"))
    broadcast_log(line)
  end

  def broadcast_completion(success, error_message = nil)
    base = { success: success, error_message: error_message, completed_at: Time.current.iso8601 }
    msg = success ? "Deployment completed successfully (Attempt ##{@attempt.attempt_number})" \
                  : "Deployment failed: #{error_message}"

    ActionCable.server.broadcast("deployment_logs_#{@deployment.uuid}", base.merge(
      type: "deployment_completed",
      message: msg,
      attempt_id: @attempt.id,
      attempt_number: @attempt.attempt_number,
      status: @attempt.status,
      duration: @attempt.duration_text
    ))

    ActionCable.server.broadcast("deployment_attempt_logs_#{@attempt.id}", base.merge(
      type: "attempt_completed",
      status: @attempt.status,
      duration: @attempt.duration_text,
      full_logs: safe_entries.join("\n")
    ))
  end

  private

  def broadcast_log(line)
    base = { message: line, timestamp: Time.current.iso8601 }

    ActionCable.server.broadcast("deployment_logs_#{@deployment.uuid}", base.merge(
      type: "log_message",
      attempt_id: @attempt.id,
      attempt_number: @attempt.attempt_number
    ))

    ActionCable.server.broadcast("deployment_attempt_logs_#{@attempt.id}", base.merge(
      type: "log_message",
      full_logs: safe_entries.join("\n")
    ))
  end

  def safe_entries
    @entries.map { |line| sanitize(line) }
  end

  def sanitize(text)
    clean = text.force_encoding("UTF-8")
    return clean if clean.valid_encoding?
    text.encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace, replace: "?")
  end
end
