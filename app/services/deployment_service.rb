class DeploymentService
  def initialize(deployment)
    @deployment = deployment
    @server = deployment.server
    @logs = []
  end

  def deploy_from_repository
    begin
      log("Starting repository deployment")
      log("Repository: #{@deployment.repository_url}")
      log("Branch: #{@deployment.repository_branch}")
      log("Target server: #{@server.name} (#{@server.ip})")
      
      # Step 1: Clone or update repository on server
      clone_result = clone_repository
      return { success: false, error: clone_result[:error], logs: @logs } unless clone_result[:success]
      
      # Step 2: Deploy to Dokku
      deploy_result = deploy_to_dokku
      return { success: false, error: deploy_result[:error], logs: @logs } unless deploy_result[:success]
      
      log("Deployment completed successfully!")
      { success: true, logs: @logs }
      
    rescue StandardError => e
      log("ERROR: #{e.message}")
      { success: false, error: e.message, logs: @logs }
    end
  end

  private

  def clone_repository
    log("Cloning repository to server...")
    
    ssh_service = SshConnectionService.new(@server)
    
    # Create deployment directory
    repo_dir = "/tmp/vantage-deployments/#{@deployment.uuid}"
    
    commands = [
      "mkdir -p #{repo_dir}",
      "cd #{repo_dir}",
      "rm -rf repo", # Clean up any existing clone
      "git clone #{@deployment.repository_url} repo",
      "cd repo",
      "git checkout #{@deployment.repository_branch}"
    ]
    
    commands.each do |command|
      log("Executing: #{command}")
      result = ssh_service.execute_command(command)
      
      if result[:success]
        log("✓ Success")
        log(result[:output]) if result[:output].present?
      else
        log("✗ Failed: #{result[:error]}")
        return { success: false, error: "Failed to clone repository: #{result[:error]}" }
      end
    end
    
    # Store the repository path for deployment
    @repo_path = "#{repo_dir}/repo"
    
    { success: true }
  end

  def deploy_to_dokku
    log("Deploying to Dokku...")
    
    ssh_service = SshConnectionService.new(@server)
    
    # Create Dokku app if it doesn't exist
    log("Ensuring Dokku app exists...")
    create_app_result = ssh_service.create_dokku_app(@deployment.dokku_app_name)
    
    if create_app_result[:success]
      log("✓ Dokku app ready")
    else
      log("✗ Failed to create Dokku app: #{create_app_result[:error]}")
      return { success: false, error: "Failed to create Dokku app: #{create_app_result[:error]}" }
    end
    
    # Deploy using git push to Dokku
    log("Pushing to Dokku...")
    
    commands = [
      "cd #{@repo_path}",
      "git remote remove dokku 2>/dev/null || true", # Remove existing remote if any
      "git remote add dokku dokku@#{@server.ip}:#{@deployment.dokku_app_name}",
      "git push dokku #{@deployment.repository_branch}:main --force"
    ]
    
    commands.each do |command|
      log("Executing: #{command}")
      result = ssh_service.execute_command(command)
      
      # Git push output can be large, so we'll log it
      if result[:output].present?
        log("Output: #{result[:output]}")
      end
      
      if result[:success]
        log("✓ Command completed")
      else
        log("✗ Command failed: #{result[:error]}")
        # Don't fail immediately on git push as Dokku might still succeed
        # We'll check the final status
      end
    end
    
    # Verify deployment by checking if the app is running
    log("Verifying deployment...")
    verify_result = verify_deployment
    
    if verify_result[:success]
      log("✓ Deployment verified successfully")
      { success: true }
    else
      log("✗ Deployment verification failed: #{verify_result[:error]}")
      { success: false, error: verify_result[:error] }
    end
  end

  def verify_deployment
    ssh_service = SshConnectionService.new(@server)
    
    # Check if the app is running
    result = ssh_service.execute_command("dokku ps:report #{@deployment.dokku_app_name}")
    
    if result[:success] && result[:output].include?("running")
      log("App is running on Dokku")
      
      # Try to get the app URL
      url_result = ssh_service.execute_command("dokku url #{@deployment.dokku_app_name}")
      if url_result[:success] && url_result[:output].present?
        app_url = url_result[:output].strip
        log("App URL: #{app_url}")
        
        # Update deployment with the URL if different
        if @deployment.dokku_url != app_url
          @deployment.update_column(:dokku_url, app_url)
        end
      end
      
      { success: true }
    else
      { success: false, error: "App is not running on Dokku" }
    end
  end

  def log(message)
    timestamp = Time.current.strftime("%H:%M:%S")
    formatted_message = "[#{timestamp}] #{message}"
    @logs << formatted_message
    Rails.logger.info "[DeploymentService] [#{@deployment.uuid}] #{message}"
  end
end