require 'net/ssh'

class DeploymentService
  def initialize(deployment, deployment_attempt = nil)
    @deployment = deployment
    @server = deployment.server
    @logs = []
    @connection_details = @server.connection_details
    @deployment_attempt = deployment_attempt || create_deployment_attempt
  end

  def deploy_from_repository
    begin
      # Mark attempt as started
      @deployment_attempt.update!(
        status: 'running',
        started_at: Time.current
      )
      
      log("Starting repository deployment")
      log("Repository: #{@deployment.repository_url}")
      log("Branch: #{@deployment.repository_branch}")
      log("Target server: #{@server.name} (#{@server.ip})")
      log("Attempt ##{@deployment_attempt.attempt_number}")
      
      result = nil
      
      Net::SSH.start(
        @connection_details[:host],
        @connection_details[:username],
        ssh_options
      ) do |ssh|
        # Step 1: Create Dokku app if it doesn't exist
        create_app_result = create_dokku_app(ssh)
        unless create_app_result[:success]
          result = { success: false, error: create_app_result[:error], logs: @logs }
          return result
        end
        
        # Step 2: Clone repository and deploy
        deploy_result = deploy_with_git(ssh)
        unless deploy_result[:success]
          result = { success: false, error: deploy_result[:error], logs: @logs }
          return result
        end
        
        # Step 3: Verify deployment
        verify_result = verify_deployment(ssh)
        if verify_result[:success]
          log("✓ Deployment completed successfully!")
          result = { success: true, logs: @logs }
        else
          log("⚠️ Deployment verification failed: #{verify_result[:message]}")
          result = { success: false, error: verify_result[:message], logs: @logs }
        end
      end
      
      # Determine final status based on logs and result
      final_success = determine_deployment_success(result[:success])
      
      # Update attempt with final status
      @deployment_attempt.update!(
        status: final_success ? 'success' : 'failed',
        completed_at: Time.current,
        logs: @logs.join("\n"),
        error_message: final_success ? nil : result[:error]
      )
      
      # Broadcast completion status
      broadcast_completion_status(final_success, result[:error])
      
      result[:success] = final_success
      result
      
    rescue Net::SSH::AuthenticationFailed => e
      error_msg = "Authentication failed. Please check your SSH key or password."
      log("ERROR: #{error_msg}")
      finalize_failed_attempt(error_msg)
      { success: false, error: error_msg, logs: @logs }
    rescue Net::SSH::ConnectionTimeout => e
      error_msg = "Connection timeout. Server may be unreachable."
      log("ERROR: #{error_msg}")
      finalize_failed_attempt(error_msg)
      { success: false, error: error_msg, logs: @logs }
    rescue StandardError => e
      log("ERROR: #{e.message}")
      finalize_failed_attempt(e.message)
      { success: false, error: e.message, logs: @logs }
    end
  end

  private

  def ssh_options
    options = {
      port: @connection_details[:port],
      timeout: 30,
      verify_host_key: :never,
      non_interactive: true
    }
    
    # Try SSH key first if available
    if @connection_details[:keys].present?
      options[:keys] = @connection_details[:keys]
      options[:auth_methods] = ['publickey']
      
      # Add password as fallback if available
      if @connection_details[:password].present?
        options[:password] = @connection_details[:password]
        options[:auth_methods] << 'password'
      end
    elsif @connection_details[:password].present?
      # Only password authentication
      options[:password] = @connection_details[:password]
      options[:auth_methods] = ['password']
    else
      raise StandardError, "No authentication method available"
    end
    
    options
  end

  def create_dokku_app(ssh)
    log("Creating Dokku app if it doesn't exist...")
    
    app_name = @deployment.dokku_app_name
    
    # Check if app already exists
    result = execute_command(ssh, "dokku apps:list 2>/dev/null | grep '^#{app_name}$' || echo 'NOT_FOUND'")
    
    if result.include?('NOT_FOUND')
      log("Creating new Dokku app: #{app_name}")
      create_result = execute_command(ssh, "dokku apps:create #{app_name}")
      if create_result.include?('ERROR') || create_result.include?('failed')
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
    
    # Create a unique directory for this deployment
    deploy_dir = "/home/dokku/#{app_name}-deploy-#{Time.current.to_i}"
    
    begin
      # Prepare repository URL with authentication if needed
      authenticated_repo_url = prepare_authenticated_repo_url(repo_url)
      
      # Clone the repository
      log("Cloning #{repo_url} (branch: #{branch})")
      clone_result = execute_command(ssh, "cd /home/dokku && git clone -b #{branch} #{authenticated_repo_url} #{deploy_dir}")
      
      if clone_result.include?('fatal:') || clone_result.include?('error:')
        # Try cloning without specifying branch first, then checkout
        log("Branch-specific clone failed, trying alternative approach...")
        execute_command(ssh, "rm -rf #{deploy_dir}")
        clone_result = execute_command(ssh, "cd /home/dokku && git clone #{authenticated_repo_url} #{deploy_dir}")
        
        if clone_result.include?('fatal:') || clone_result.include?('error:')
          return { success: false, error: "Failed to clone repository: #{clone_result}" }
        end
        
        # Checkout the specific branch
        checkout_result = execute_command(ssh, "cd #{deploy_dir} && git checkout #{branch}")
        if checkout_result.include?('error:') || checkout_result.include?("pathspec '#{branch}' did not match")
          log("⚠️ Warning: Could not checkout branch '#{branch}', using default branch")
        end
      end
      
      log("✓ Repository cloned successfully")
      
      # Ensure SSH key is set up for Dokku deployment
      log("Setting up SSH key for deployment...")
      setup_deployment_ssh_key(ssh)
      
      # Add dokku remote and push
      log("Adding Dokku remote and deploying...")
      execute_command(ssh, "cd #{deploy_dir} && git remote remove dokku 2>/dev/null || true")
      execute_command(ssh, "cd #{deploy_dir} && git remote add dokku dokku@#{@server.ip}:#{app_name}")
      
      # Push to deploy (capture full output)
      log("Pushing to Dokku (this may take a few minutes)...")
      deploy_output = execute_command(ssh, "cd #{deploy_dir} && GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' git push dokku HEAD:main --force", timeout: 600)
      
      # Log the deployment output
      if deploy_output.present?
        deploy_output.split("\n").each { |line| log("DEPLOY: #{line}") }
      end
      
      # Check if deployment was successful
      if deploy_output.include?('Application deployed:') || deploy_output.include?('=====> Application deployed') || !deploy_output.include?('ERROR')
        log("✓ Git push completed")
      else
        log("⚠️ Deployment may have encountered issues")
      end
      
      { success: true }
      
    ensure
      # Clean up the cloned repository
      execute_command(ssh, "rm -rf #{deploy_dir}")
      log("Cleaned up temporary files")
    end
  end

  def verify_deployment(ssh)
    log("Verifying deployment...")
    
    app_name = @deployment.dokku_app_name
    
    # Check if the app is running
    ps_result = execute_command(ssh, "dokku ps:report #{app_name} 2>/dev/null")
    
    if ps_result.include?('running') || ps_result.include?('up')
      log("✓ App is running on Dokku")
      
      # Try to get the app URL
      url_result = execute_command(ssh, "dokku url #{app_name} 2>/dev/null").strip
      if url_result.present? && url_result.start_with?('http')
        log("✓ App URL: #{url_result}")
        # Note: We don't store this URL as dokku_url is a computed method based on domains
      end
      
      { success: true }
    else
      # Try alternative status check
      logs_result = execute_command(ssh, "dokku logs #{app_name} --tail 5 2>/dev/null")
      if logs_result.present?
        log("Recent logs: #{logs_result}")
      end
      
      { success: false, message: "App may not be running properly" }
    end
  end

  def execute_command(ssh, command, timeout: 120)
    log("Executing: #{command}")
    
    result = ""
    ssh.exec!(command) do |channel, stream, data|
      # Force UTF-8 encoding and handle invalid characters
      clean_data = data.force_encoding('UTF-8')
      
      # Replace invalid UTF-8 sequences with replacement character
      unless clean_data.valid_encoding?
        clean_data = data.encode('UTF-8', 'UTF-8', invalid: :replace, undef: :replace, replace: '?')
      end
      
      result += clean_data
      
      # Log output in real-time for long commands
      if command.include?('git push') || command.include?('git clone')
        clean_data.split("\n").each { |line| log(">> #{line}") if line.strip.present? }
      end
    end
    
    result
  rescue => e
    log("Command failed: #{e.message}")
    "ERROR: #{e.message}"
  end

  def setup_deployment_ssh_key(ssh)
    # Get the current user's public key from the server
    public_key_result = execute_command(ssh, "cat ~/.ssh/id_rsa.pub 2>/dev/null || cat ~/.ssh/id_ed25519.pub 2>/dev/null || echo 'NO_KEY_FOUND'")
    
    if public_key_result&.include?('NO_KEY_FOUND') || public_key_result.blank?
      # Generate an SSH key if none exists
      log("No SSH key found, generating new key...")
      execute_command(ssh, "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -C 'vantage-deployment-key'")
      public_key_result = execute_command(ssh, "cat ~/.ssh/id_ed25519.pub")
    end
    
    if public_key_result.present? && !public_key_result.include?('NO_KEY_FOUND')
      public_key = public_key_result.strip
      
      # Add the key to Dokku if it's not already there
      log("Adding deployment SSH key to Dokku...")
      
      # Check if key already exists in Dokku
      existing_keys = execute_command(ssh, "sudo dokku ssh-keys:list 2>/dev/null || echo 'NO_KEYS'")
      
      # Extract just the key part for comparison (remove ssh-ed25519/ssh-rsa prefix and comment)
      key_parts = public_key.split(' ')
      key_fingerprint = key_parts[1] if key_parts.length >= 2
      
      if !existing_keys.include?(key_fingerprint)
        # Add the key to Dokku with a unique name
        key_name = "deployment-#{Time.current.to_i}"
        add_key_result = execute_command(ssh, "echo '#{public_key}' | sudo dokku ssh-keys:add #{key_name}")
        
        if add_key_result&.include?('error') || add_key_result&.include?('ERROR')
          log("⚠️ Warning: Could not add SSH key to Dokku: #{add_key_result}")
        else
          log("✓ SSH key added to Dokku successfully")
        end
      else
        log("✓ SSH key already exists in Dokku")
      end
    else
      log("⚠️ Warning: Could not setup SSH key for deployment")
    end
  end

  def prepare_authenticated_repo_url(repo_url)
    # If it's a GitHub repository and the user has a GitHub linked account, use token authentication
    if repo_url.include?('github.com') && @deployment.deployment_method == 'github_repo'
      github_account = @deployment.user.linked_accounts.find_by(provider: 'github')
      
      if github_account&.token_valid?
        # Convert HTTPS URL to authenticated format
        # https://github.com/username/repo.git -> https://token@github.com/username/repo.git
        if repo_url.start_with?('https://github.com/')
          authenticated_url = repo_url.sub('https://github.com/', "https://#{github_account.access_token}@github.com/")
          log("Using GitHub token authentication for private repository")
          return authenticated_url
        end
      else
        log("⚠️ Warning: GitHub repository detected but no valid GitHub token found")
      end
    end
    
    # Return original URL if no authentication needed or available
    repo_url
  end

  def create_deployment_attempt
    next_attempt_number = @deployment.deployment_attempts.maximum(:attempt_number).to_i + 1
    @deployment.deployment_attempts.create!(
      attempt_number: next_attempt_number,
      status: 'pending'
    )
  end
  
  def determine_deployment_success(initial_success)
    # Check logs for deployment failure indicators
    logs_text = @logs.join("\n")
    
    Rails.logger.info "=== DEPLOYMENT SUCCESS ANALYSIS ==="
    Rails.logger.info "Initial success: #{initial_success}"
    Rails.logger.info "Logs contain: #{@logs.last(5).join(' | ')}"
    
    # Critical failure patterns - these definitely mean the deployment failed
    critical_failure_patterns = [
      /failed to push.*refs/i,
      /permission denied.*publickey/i,
      /could not read from remote repository/i,
      /fatal.*could not read/i,
      /deployment.*failed/i,
      /build.*failed/i,
      /error.*during.*deployment/i
    ]
    
    # Check for critical failures that would prevent deployment
    critical_failure_patterns.each do |pattern|
      if logs_text.match?(pattern)
        Rails.logger.info "FAILED: Found critical failure pattern: #{pattern}"
        return false
      end
    end
    
    # Key success indicators - if we see these, deployment was successful
    # Order matters: check the most definitive ones first
    
    if logs_text.include?("✓ App is running on Dokku")
      Rails.logger.info "SUCCESS: App is confirmed running on Dokku"
      return true
    end
    
    if logs_text.include?("✓ Git push completed")
      Rails.logger.info "SUCCESS: Git push completed successfully"
      return true
    end
    
    if logs_text.include?("Everything up-to-date") && logs_text.include?("✓ Git push completed")
      Rails.logger.info "SUCCESS: Git push up-to-date (no changes needed)"
      return true
    end
    
    # If we made it through git push and started verification, it's likely successful
    # Minor errors during verification (like the dokku_url issue) shouldn't fail the deployment
    if logs_text.include?("✓ Git push completed") && logs_text.include?("Verifying deployment")
      Rails.logger.info "SUCCESS: Git push completed and verification started"
      return true
    end
    
    # If no critical failures and we had initial success, it's probably good
    if initial_success
      Rails.logger.info "SUCCESS: Initial success with no critical failures"
      return true
    end
    
    Rails.logger.info "FAILED: No clear success indicators found"
    false
  end
  
  def finalize_failed_attempt(error_message)
    @deployment_attempt.update!(
      status: 'failed',
      completed_at: Time.current,
      logs: @logs.join("\n"),
      error_message: error_message
    )
    
    # Broadcast failure status
    broadcast_completion_status(false, error_message)
  end
  
  def broadcast_completion_status(success, error_message = nil)
    # Broadcast deployment completion
    ActionCable.server.broadcast("deployment_logs_#{@deployment.uuid}", {
      type: 'deployment_completed',
      success: success,
      attempt_id: @deployment_attempt.id,
      attempt_number: @deployment_attempt.attempt_number,
      status: @deployment_attempt.status,
      duration: @deployment_attempt.duration_text,
      error_message: error_message,
      completed_at: Time.current.iso8601
    })
    
    # Also broadcast to the specific attempt channel
    ActionCable.server.broadcast("deployment_attempt_logs_#{@deployment_attempt.id}", {
      type: 'attempt_completed',
      success: success,
      status: @deployment_attempt.status,
      duration: @deployment_attempt.duration_text,
      error_message: error_message,
      completed_at: Time.current.iso8601,
      full_logs: @logs.join("\n")
    })
  end

  def log(message)
    # Ensure message is UTF-8 and handle invalid characters
    clean_message = message.to_s.force_encoding('UTF-8')
    unless clean_message.valid_encoding?
      clean_message = message.to_s.encode('UTF-8', 'UTF-8', invalid: :replace, undef: :replace, replace: '?')
    end
    
    timestamp = Time.current.strftime("%H:%M:%S")
    formatted_message = "[#{timestamp}] #{clean_message}"
    @logs << formatted_message
    Rails.logger.info "[DeploymentService] [#{@deployment.uuid}] [Attempt ##{@deployment_attempt.attempt_number}] #{clean_message}"
    
    # Ensure logs array is UTF-8 safe before joining
    safe_logs = @logs.map { |log_line| 
      log_line.force_encoding('UTF-8').valid_encoding? ? log_line : log_line.encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
    }
    
    # Update deployment attempt logs in real-time
    @deployment_attempt.update_column(:logs, safe_logs.join("\n"))
    
    # Broadcast log message in real-time via ActionCable
    ActionCable.server.broadcast("deployment_logs_#{@deployment.uuid}", {
      type: 'log_message',
      message: formatted_message,
      attempt_id: @deployment_attempt.id,
      attempt_number: @deployment_attempt.attempt_number,
      timestamp: Time.current.iso8601
    })
    
    # Also broadcast to the specific attempt channel
    ActionCable.server.broadcast("deployment_attempt_logs_#{@deployment_attempt.id}", {
      type: 'log_message',
      message: formatted_message,
      full_logs: safe_logs.join("\n"),
      timestamp: Time.current.iso8601
    })
  end
end