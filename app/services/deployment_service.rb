require "net/ssh"

class DeploymentService
  DEPLOY_TIMEOUT = 600

  def initialize(deployment, deployment_attempt = nil)
    @deployment = deployment
    @server = deployment.server
    @connection_details = @server.connection_details
    @deployment_attempt = deployment_attempt || create_deployment_attempt
    @logger = Deployment::Logger.new(@deployment, @deployment_attempt)
  end

  def deploy_from_repository
    @deployment_attempt.update!(status: "running", started_at: Time.current)

    log("Starting repository deployment")
    log("Repository: #{@deployment.repository_url}")
    log("Branch: #{@deployment.repository_branch}")
    log("Target server: #{@server.name} (#{@server.ip})")
    log("Attempt ##{@deployment_attempt.attempt_number}")

    result = nil

    Net::SSH.start(@connection_details[:host], @connection_details[:username], ssh_options) do |ssh|
      create_result = create_dokku_app(ssh)
      return finalize(false, create_result[:error]) unless create_result[:success]

      deploy_result = deploy_with_git(ssh)
      return finalize(false, deploy_result[:error]) unless deploy_result[:success]

      verify_result = verify_deployment(ssh)
      if verify_result[:success]
        log("✓ Deployment completed successfully!")
        result = { success: true }
      else
        log("⚠️ Deployment verification failed: #{verify_result[:message]}")
        result = { success: false, error: verify_result[:message] }
      end
    end

    finalize(determine_deployment_success(result[:success]), result[:error])

  rescue Net::SSH::AuthenticationFailed
    finalize(false, "Authentication failed. Please check your SSH key or password.")
  rescue Net::SSH::ConnectionTimeout
    finalize(false, "Connection timeout. Server may be unreachable.")
  rescue StandardError => e
    finalize(false, e.message)
  end

  private

  def finalize(success, error_message = nil)
    log("ERROR: #{error_message}") if !success && error_message
    @deployment_attempt.update!(
      status: success ? "success" : "failed",
      completed_at: Time.current,
      logs: @logger.entries.join("\n"),
      error_message: success ? nil : error_message
    )
    @logger.broadcast_completion(success, error_message)
    { success: success, error: error_message, logs: @logger.entries }
  end

  def log(message)
    @logger.log(message)
  end

  def ssh_options
    options = {
      port: @connection_details[:port],
      timeout: 30,
      verify_host_key: :never,
      non_interactive: true
    }

    if @connection_details[:keys].present?
      options[:keys] = @connection_details[:keys]
      options[:auth_methods] = [ "publickey" ]
      if @connection_details[:password].present?
        options[:password] = @connection_details[:password]
        options[:auth_methods] << "password"
      end
    elsif @connection_details[:password].present?
      options[:password] = @connection_details[:password]
      options[:auth_methods] = [ "password" ]
    else
      raise StandardError, "No authentication method available"
    end

    options
  end

  def create_dokku_app(ssh)
    log("Creating Dokku app if it doesn't exist...")
    app_name = @deployment.dokku_app_name
    result = execute_command(ssh, "dokku apps:list 2>/dev/null | grep '^#{app_name}$' || echo 'NOT_FOUND'")

    if result.include?("NOT_FOUND")
      log("Creating new Dokku app: #{app_name}")
      create_result = execute_command(ssh, "dokku apps:create #{app_name}")
      if create_result.include?("ERROR") || create_result.include?("failed")
        return { success: false, error: "Failed to create Dokku app: #{create_result}" }
      end
      log("✓ Dokku app created successfully")
    else
      log("✓ Dokku app already exists")
    end

    { success: true }
  end

  def deploy_with_git(ssh)
    log("Cloning repository and deploying...")

    app_name = @deployment.dokku_app_name
    repo_url = @deployment.repository_url
    branch = @deployment.repository_branch
    deploy_dir = "/home/dokku/#{app_name}-deploy-#{Time.current.to_i}"

    begin
      authenticated_repo_url = prepare_authenticated_repo_url(repo_url)

      log("Cloning #{repo_url} (branch: #{branch})")
      clone_result = execute_command(ssh, "cd /home/dokku && git clone -b #{branch} #{authenticated_repo_url} #{deploy_dir}")

      if clone_result.include?("fatal:") || clone_result.include?("error:")
        log("Branch-specific clone failed, trying alternative approach...")
        execute_command(ssh, "rm -rf #{deploy_dir}")
        clone_result = execute_command(ssh, "cd /home/dokku && git clone #{authenticated_repo_url} #{deploy_dir}")

        if clone_result.include?("fatal:") || clone_result.include?("error:")
          return { success: false, error: "Failed to clone repository: #{clone_result}" }
        end

        checkout_result = execute_command(ssh, "cd #{deploy_dir} && git checkout #{branch}")
        if checkout_result.include?("error:") || checkout_result.include?("pathspec '#{branch}' did not match")
          log("⚠️ Warning: Could not checkout branch '#{branch}', using default branch")
        end
      end

      log("✓ Repository cloned successfully")

      log("Setting up SSH key for deployment...")
      setup_deployment_ssh_key(ssh)

      log("Adding Dokku remote and deploying...")
      execute_command(ssh, "cd #{deploy_dir} && git remote remove dokku 2>/dev/null || true")
      execute_command(ssh, "cd #{deploy_dir} && git remote add dokku dokku@#{@server.ip}:#{app_name}")

      log("Pushing to Dokku (this may take a few minutes)...")
      deploy_output = execute_command(ssh, "cd #{deploy_dir} && GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' git push dokku HEAD:main --force", timeout: DEPLOY_TIMEOUT)

      deploy_output.split("\n").each { |line| log("DEPLOY: #{line}") } if deploy_output.present?

      if deploy_output.include?("Application deployed:") || deploy_output.include?("=====> Application deployed") || !deploy_output.include?("ERROR")
        log("✓ Git push completed")
      else
        log("⚠️ Deployment may have encountered issues")
      end

      { success: true }
    ensure
      execute_command(ssh, "rm -rf #{deploy_dir}")
      log("Cleaned up temporary files")
    end
  end

  def verify_deployment(ssh)
    log("Verifying deployment...")
    app_name = @deployment.dokku_app_name
    ps_result = execute_command(ssh, "dokku ps:report #{app_name} 2>/dev/null")

    if ps_result.include?("running") || ps_result.include?("up")
      log("✓ App is running on Dokku")
      url_result = execute_command(ssh, "dokku url #{app_name} 2>/dev/null").strip
      log("✓ App URL: #{url_result}") if url_result.present? && url_result.start_with?("http")
      { success: true }
    else
      logs_result = execute_command(ssh, "dokku logs #{app_name} --tail 5 2>/dev/null")
      log("Recent logs: #{logs_result}") if logs_result.present?
      { success: false, message: "App may not be running properly" }
    end
  end

  def execute_command(ssh, command, timeout: 120)
    log("Executing: #{command}")
    result = ""

    ssh.exec!(command) do |_channel, _stream, data|
      clean_data = data.force_encoding("UTF-8")
      unless clean_data.valid_encoding?
        clean_data = data.encode("UTF-8", "UTF-8", invalid: :replace, undef: :replace, replace: "?")
      end
      result += clean_data
      if command.include?("git push") || command.include?("git clone")
        clean_data.split("\n").each { |line| log(">> #{line}") if line.strip.present? }
      end
    end

    result
  rescue => e
    log("Command failed: #{e.message}")
    "ERROR: #{e.message}"
  end

  def setup_deployment_ssh_key(ssh)
    public_key_result = execute_command(ssh, "cat ~/.ssh/id_rsa.pub 2>/dev/null || cat ~/.ssh/id_ed25519.pub 2>/dev/null || echo 'NO_KEY_FOUND'")

    if public_key_result&.include?("NO_KEY_FOUND") || public_key_result.blank?
      log("No SSH key found, generating new key...")
      execute_command(ssh, "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -C 'vantage-deployment-key'")
      public_key_result = execute_command(ssh, "cat ~/.ssh/id_ed25519.pub")
    end

    return unless public_key_result.present? && !public_key_result.include?("NO_KEY_FOUND")

    public_key = public_key_result.strip
    log("Adding deployment SSH key to Dokku...")
    existing_keys = execute_command(ssh, "sudo dokku ssh-keys:list 2>/dev/null || echo 'NO_KEYS'")
    key_fingerprint = public_key.split(" ")[1]

    if !existing_keys.include?(key_fingerprint)
      key_name = "deployment-#{Time.current.to_i}"
      add_result = execute_command(ssh, "echo '#{public_key}' | sudo dokku ssh-keys:add #{key_name}")
      if add_result&.include?("error") || add_result&.include?("ERROR")
        log("⚠️ Warning: Could not add SSH key to Dokku: #{add_result}")
      else
        log("✓ SSH key added to Dokku successfully")
      end
    else
      log("✓ SSH key already exists in Dokku")
    end
  end

  def prepare_authenticated_repo_url(repo_url)
    if repo_url.include?("github.com") && @deployment.deployment_method == "github_repo"
      github_account = @deployment.user.linked_accounts.find_by(provider: "github")
      if github_account&.token_valid?
        if repo_url.start_with?("https://github.com/")
          log("Using GitHub token authentication for private repository")
          return repo_url.sub("https://github.com/", "https://#{github_account.access_token}@github.com/")
        end
      else
        log("⚠️ Warning: GitHub repository detected but no valid GitHub token found")
      end
    end
    repo_url
  end

  def create_deployment_attempt
    next_number = @deployment.deployment_attempts.maximum(:attempt_number).to_i + 1
    @deployment.deployment_attempts.create!(attempt_number: next_number, status: "pending")
  end

  def determine_deployment_success(initial_success)
    logs_text = @logger.entries.join("\n")

    critical_failure_patterns = [
      /failed to push.*refs/i,
      /permission denied.*publickey/i,
      /could not read from remote repository/i,
      /fatal.*could not read/i,
      /deployment.*failed/i,
      /build.*failed/i,
      /error.*during.*deployment/i
    ]

    return false if critical_failure_patterns.any? { |p| logs_text.match?(p) }

    return true if logs_text.include?("✓ App is running on Dokku")
    return true if logs_text.include?("✓ Git push completed")
    return true if initial_success

    false
  end
end
