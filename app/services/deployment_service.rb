require 'net/ssh'

class DeploymentService
  def initialize(deployment)
    @deployment = deployment
    @server = deployment.server
    @logs = []
    @connection_details = @server.connection_details
  end

  def deploy_from_repository
    begin
      log("Starting repository deployment")
      log("Repository: #{@deployment.repository_url}")
      log("Branch: #{@deployment.repository_branch}")
      log("Target server: #{@server.name} (#{@server.ip})")
      
      Net::SSH.start(
        @connection_details[:host],
        @connection_details[:username],
        ssh_options
      ) do |ssh|
        # Step 1: Create Dokku app if it doesn't exist
        create_app_result = create_dokku_app(ssh)
        return { success: false, error: create_app_result[:error], logs: @logs } unless create_app_result[:success]
        
        # Step 2: Clone repository and deploy
        deploy_result = deploy_with_git(ssh)
        return { success: false, error: deploy_result[:error], logs: @logs } unless deploy_result[:success]
        
        # Step 3: Verify deployment
        verify_result = verify_deployment(ssh)
        if verify_result[:success]
          log("✓ Deployment completed successfully!")
        else
          log("⚠️ Deployment may have issues: #{verify_result[:message]}")
        end
      end
      
      { success: true, logs: @logs }
      
    rescue Net::SSH::AuthenticationFailed => e
      error_msg = "Authentication failed. Please check your SSH key or password."
      log("ERROR: #{error_msg}")
      { success: false, error: error_msg, logs: @logs }
    rescue Net::SSH::ConnectionTimeout => e
      error_msg = "Connection timeout. Server may be unreachable."
      log("ERROR: #{error_msg}")
      { success: false, error: error_msg, logs: @logs }
    rescue StandardError => e
      log("ERROR: #{e.message}")
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
      # Clone the repository
      log("Cloning #{repo_url} (branch: #{branch})")
      clone_result = execute_command(ssh, "cd /home/dokku && git clone -b #{branch} #{repo_url} #{deploy_dir}")
      
      if clone_result.include?('fatal:') || clone_result.include?('error:')
        # Try cloning without specifying branch first, then checkout
        log("Branch-specific clone failed, trying alternative approach...")
        execute_command(ssh, "rm -rf #{deploy_dir}")
        clone_result = execute_command(ssh, "cd /home/dokku && git clone #{repo_url} #{deploy_dir}")
        
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
      
      # Add dokku remote and push
      log("Adding Dokku remote and deploying...")
      execute_command(ssh, "cd #{deploy_dir} && git remote remove dokku 2>/dev/null || true")
      execute_command(ssh, "cd #{deploy_dir} && git remote add dokku dokku@localhost:#{app_name}")
      
      # Push to deploy (capture full output)
      log("Pushing to Dokku (this may take a few minutes)...")
      deploy_output = execute_command(ssh, "cd #{deploy_dir} && git push dokku HEAD:main --force", timeout: 600)
      
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
        
        # Update deployment with the URL if different
        if @deployment.dokku_url != url_result
          @deployment.update_column(:dokku_url, url_result)
        end
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
      result += data
      # Log output in real-time for long commands
      if command.include?('git push') || command.include?('git clone')
        data.split("\n").each { |line| log(">> #{line}") if line.strip.present? }
      end
    end
    
    result
  rescue => e
    log("Command failed: #{e.message}")
    "ERROR: #{e.message}"
  end

  def log(message)
    timestamp = Time.current.strftime("%H:%M:%S")
    formatted_message = "[#{timestamp}] #{message}"
    @logs << formatted_message
    Rails.logger.info "[DeploymentService] [#{@deployment.uuid}] #{message}"
    
    # Update deployment logs in real-time
    current_logs = @deployment.deployment_logs || ""
    updated_logs = current_logs + "\n#{formatted_message}"
    @deployment.update_column(:deployment_logs, updated_logs)
  end
end