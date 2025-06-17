class DeploymentsController < ApplicationController
  include ActivityTrackable
  
  before_action :set_deployment, only: [:show, :edit, :update, :destroy, :git_configuration, :update_git_configuration, :deploy, :logs, :configure_domain, :update_domains, :attach_ssh_keys, :update_ssh_keys, :configure_databases, :update_database_configuration, :delete_database_configuration, :create_dokku_app, :manage_environment, :update_environment, :check_ssl_status]
  before_action :authorize_deployment, only: [:show, :edit, :update, :destroy, :git_configuration, :update_git_configuration, :deploy, :logs, :configure_domain, :update_domains, :attach_ssh_keys, :update_ssh_keys, :configure_databases, :update_database_configuration, :delete_database_configuration, :create_dokku_app, :manage_environment, :update_environment, :check_ssl_status]
  
  def index
    @pagy, @deployments = pagy(current_user.deployments.includes(:server).recent, limit: 15)
    log_activity('deployments_list_viewed', details: "Viewed deployments list (#{@deployments.count} deployments)")
  end

  def show
    log_activity('deployment_viewed', details: "Viewed deployment: #{@deployment.display_name}")
  end

  def new
    @deployment = current_user.deployments.build
    @available_servers = current_user.servers.where.not(dokku_version: [nil, ""])
    authorize @deployment
    
    if @available_servers.empty?
      toast_error("You need at least one server with Dokku installed to create a deployment.", title: "No Dokku Servers")
      redirect_to deployments_path
    end
  end

  def create
    @deployment = current_user.deployments.build(deployment_params)
    @available_servers = current_user.servers.where.not(dokku_version: [nil, ""])
    authorize @deployment
    
    if @deployment.save
      log_activity('deployment_created', details: "Created deployment: #{@deployment.display_name}")
      toast_success("Deployment '#{@deployment.name}' created successfully with Dokku app name '#{@deployment.dokku_app_name}'!", title: "Deployment Created")
      redirect_to @deployment
    else
      toast_error("Failed to create deployment. Please check the form for errors.", title: "Creation Failed")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @available_servers = current_user.servers.where.not(dokku_version: [nil, ""])
    # Include current server even if it no longer has Dokku (for editing existing deployments)
    @available_servers = @available_servers.or(Server.where(id: @deployment.server_id))
  end

  def update
    @available_servers = current_user.servers.where.not(dokku_version: [nil, ""])
    @available_servers = @available_servers.or(Server.where(id: @deployment.server_id))
    
    if @deployment.update(deployment_params)
      log_activity('deployment_updated', details: "Updated deployment: #{@deployment.display_name}")
      toast_success("Deployment '#{@deployment.name}' updated successfully!", title: "Deployment Updated")
      redirect_to @deployment
    else
      toast_error("Failed to update deployment. Please check the form for errors.", title: "Update Failed")
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    deployment_name = @deployment.name
    @deployment.destroy
    log_activity('deployment_deleted', details: "Deleted deployment: #{deployment_name}")
    toast_success("Deployment '#{deployment_name}' deleted successfully!", title: "Deployment Deleted")
    redirect_to deployments_path
  end

  def create_dokku_app
    begin
      service = SshConnectionService.new(@deployment.server)
      result = service.create_dokku_app(@deployment.dokku_app_name)
      
      if result[:success]
        log_activity('dokku_app_created', details: "Created Dokku app: #{@deployment.dokku_app_name} on server: #{@deployment.server.name}")
        toast_success("Dokku app '#{@deployment.dokku_app_name}' created successfully!", title: "App Created")
        # Update deployment status here in future
      else
        log_activity('dokku_app_creation_failed', details: "Failed to create Dokku app: #{@deployment.dokku_app_name} - #{result[:error]}")
        toast_error("Failed to create Dokku app: #{result[:error]}", title: "Creation Failed")
      end
    rescue StandardError => e
      Rails.logger.error "Dokku app creation failed: #{e.message}"
      toast_error("An unexpected error occurred: #{e.message}", title: "Creation Error")
    end
    
    redirect_to @deployment
  end

  def configure_domain
    @domains = @deployment.domains.ordered
    log_activity('domains_viewed', details: "Viewed domain configuration for deployment: #{@deployment.display_name}")
  end

  def update_domains
    begin
      domains_params = params[:domains] || {}
      
      # Start a transaction to ensure data consistency
      ActiveRecord::Base.transaction do
        # Clear existing domains
        @deployment.domains.destroy_all
        
        # Create new domains from the form
        domains_params.each do |index, domain_data|
          domain_name = domain_data[:name]&.strip&.downcase
          is_default = domain_data[:default_domain] == '1'
          
          # Skip empty entries
          next if domain_name.blank?
          
          @deployment.domains.create!(
            name: domain_name,
            default_domain: is_default
          )
        end
        
        # If no domain was marked as default, make the first one default
        if @deployment.domains.any? && !@deployment.domains.exists?(default_domain: true)
          @deployment.domains.first.update!(default_domain: true)
        end
        
        # Sync domains to Dokku server and configure SSL
        service = SshConnectionService.new(@deployment.server)
        domain_names = @deployment.domains.pluck(:name)
        result = service.sync_dokku_domains(@deployment.dokku_app_name, domain_names)
        
        if result[:success]
          count = @deployment.domains.count
          log_activity('domains_updated', 
                      details: "Updated domains for deployment: #{@deployment.display_name} - #{count} domain#{'s' unless count == 1} configured")
          toast_success("Domains updated successfully! #{count} domain#{'s' unless count == 1} configured and SSL enabled.", 
                       title: "Domains Updated")
        else
          log_activity('domains_sync_failed', 
                      details: "Failed to sync domains for deployment: #{@deployment.display_name} - #{result[:error]}")
          toast_error("Failed to sync domains to server: #{result[:error]}", title: "Sync Failed")
          # Rollback the transaction since server sync failed
          raise ActiveRecord::Rollback
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      toast_error("Failed to save domains: #{e.record.errors.full_messages.join(', ')}", title: "Validation Error")
    rescue StandardError => e
      Rails.logger.error "Domains update failed: #{e.message}"
      toast_error("An unexpected error occurred: #{e.message}", title: "Update Error")
    end
    
    redirect_to configure_domain_deployment_path(@deployment)
  end

  def attach_ssh_keys
    @available_ssh_keys = current_user.ssh_keys.active.order(:name)
    @attached_ssh_keys = @deployment.ssh_keys
    log_activity('ssh_keys_attachment_viewed', details: "Viewed SSH key attachment for deployment: #{@deployment.display_name}")
  end

  def update_ssh_keys
    begin
      ssh_key_ids = params[:ssh_key_ids] || []
      
      # Get SSH keys to attach and detach
      new_ssh_keys = current_user.ssh_keys.where(id: ssh_key_ids)
      current_ssh_keys = @deployment.ssh_keys
      
      keys_to_attach = new_ssh_keys - current_ssh_keys
      keys_to_detach = current_ssh_keys - new_ssh_keys
      
      # Update the associations
      @deployment.ssh_keys = new_ssh_keys
      
      # Sync keys to Dokku server
      service = SshConnectionService.new(@deployment.server)
      result = service.sync_dokku_ssh_keys(@deployment.ssh_keys.pluck(:public_key))
      
      if result[:success]
        attached_count = keys_to_attach.count
        detached_count = keys_to_detach.count
        
        message_parts = []
        message_parts << "#{attached_count} key#{'s' unless attached_count == 1} attached" if attached_count > 0
        message_parts << "#{detached_count} key#{'s' unless detached_count == 1} detached" if detached_count > 0
        message_parts << "No changes made" if attached_count == 0 && detached_count == 0
        
        log_activity('ssh_keys_updated', details: "Updated SSH keys for deployment: #{@deployment.display_name} - #{message_parts.join(', ')}")
        toast_success("SSH keys updated successfully! #{message_parts.join(', ').capitalize}.", title: "Keys Updated")
      else
        log_activity('ssh_keys_sync_failed', details: "Failed to sync SSH keys for deployment: #{@deployment.display_name} - #{result[:error]}")
        toast_error("Failed to sync SSH keys to server: #{result[:error]}", title: "Sync Failed")
      end
    rescue StandardError => e
      Rails.logger.error "SSH key update failed: #{e.message}"
      toast_error("An unexpected error occurred: #{e.message}", title: "Update Error")
    end
    
    redirect_to attach_ssh_keys_deployment_path(@deployment)
  end

  def configure_databases
    @database_configuration = @deployment.database_configuration || @deployment.build_database_configuration
    @available_databases = DatabaseConfiguration::SUPPORTED_DATABASES
    @redis_config = DatabaseConfiguration::REDIS_CONFIG
    
    # Check for environment variable conflicts
    @has_conflicts = @database_configuration.has_environment_variable_conflict?.any?
    
    log_activity('database_configuration_viewed', details: "Viewed database configuration for deployment: #{@deployment.display_name}")
  end

  def update_database_configuration
    begin
      database_params = params[:database_configuration] || {}
      
      @database_configuration = @deployment.database_configuration || @deployment.build_database_configuration
      
      # Set the parameters
      @database_configuration.assign_attributes(
        database_type: database_params[:database_type],
        redis_enabled: database_params[:redis_enabled] == '1'
      )
      
      if @database_configuration.save
        # Configure database on server
        service = SshConnectionService.new(@deployment.server)
        result = service.configure_database(@deployment.dokku_app_name, @database_configuration)
        
        if result[:success]
          @database_configuration.update!(
            configured: true,
            configuration_output: result[:output],
            error_message: nil
          )
          
          log_activity('database_configured', 
                      details: "Configured #{@database_configuration.display_name} database for deployment: #{@deployment.display_name}")
          
          success_message = "Database configured successfully! "
          success_message += "#{@database_configuration.display_name} (#{@database_configuration.database_name})"
          success_message += " and #{@database_configuration.redis_display_name}" if @database_configuration.redis_enabled?
          success_message += " are now available."
          
          toast_success(success_message, title: "Database Configured")
        else
          @database_configuration.update!(
            configured: false,
            configuration_output: result[:output],
            error_message: result[:error]
          )
          
          log_activity('database_configuration_failed', 
                      details: "Failed to configure database for deployment: #{@deployment.display_name} - #{result[:error]}")
          toast_error("Failed to configure database: #{result[:error]}", title: "Configuration Failed")
        end
      else
        toast_error("Failed to save database configuration: #{@database_configuration.errors.full_messages.join(', ')}", title: "Validation Error")
      end
    rescue StandardError => e
      Rails.logger.error "Database configuration failed: #{e.message}"
      toast_error("An unexpected error occurred: #{e.message}", title: "Configuration Error")
    end
    
    redirect_to configure_databases_deployment_path(@deployment)
  end

  def delete_database_configuration
    begin
      @database_configuration = @deployment.database_configuration
      
      if @database_configuration.nil?
        toast_error("No database configuration found to delete", title: "Not Found")
        redirect_to configure_databases_deployment_path(@deployment)
        return
      end
      
      unless @database_configuration.can_be_deleted?
        toast_error("Database configuration cannot be deleted in its current state", title: "Cannot Delete")
        redirect_to configure_databases_deployment_path(@deployment)
        return
      end
      
      # Detach and delete database on server
      service = SshConnectionService.new(@deployment.server)
      result = service.delete_database_configuration(@deployment.dokku_app_name, @database_configuration)
      
      if result[:success]
        # Delete the database configuration record
        db_name = @database_configuration.database_name
        redis_name = @database_configuration.redis_name if @database_configuration.redis_enabled?
        display_name = @database_configuration.display_name
        
        @database_configuration.destroy!
        
        log_activity('database_deleted', 
                    details: "Deleted #{display_name} database configuration for deployment: #{@deployment.display_name}")
        
        success_message = "Database configuration deleted successfully! "
        success_message += "#{display_name} database (#{db_name})"
        success_message += " and Redis instance (#{redis_name})" if redis_name
        success_message += " have been detached and deleted."
        
        toast_success(success_message, title: "Database Deleted")
      else
        log_activity('database_deletion_failed', 
                    details: "Failed to delete database configuration for deployment: #{@deployment.display_name} - #{result[:error]}")
        toast_error("Failed to delete database: #{result[:error]}", title: "Deletion Failed")
      end
    rescue StandardError => e
      Rails.logger.error "Database deletion failed: #{e.message}"
      toast_error("An unexpected error occurred: #{e.message}", title: "Deletion Error")
    end
    
    redirect_to configure_databases_deployment_path(@deployment)
  end

  def manage_environment
    @environment_variables = @deployment.environment_variables.ordered
    log_activity('environment_variables_viewed', details: "Viewed environment variables for deployment: #{@deployment.display_name}")
  end

  def update_environment
    begin
      env_vars_params = params[:environment_variables] || {}
      
      # Convert parameters to a serializable hash for the job
      env_vars_hash = env_vars_params.to_unsafe_h
      
      # Start the environment variables update in the background
      UpdateEnvironmentJob.perform_later(@deployment.id, current_user.id, env_vars_hash)
      
      log_activity('environment_variables_update_started', 
                  details: "Started environment variables update for deployment: #{@deployment.display_name}")
      
      respond_to do |format|
        format.json do
          render json: {
            success: true,
            message: "Environment variables update started in background. You'll be notified when complete.",
            deployment_uuid: @deployment.uuid
          }
        end
        format.html do
          toast_info("Environment variables update started. You'll be notified when complete.", title: "Update Started")
          redirect_to manage_environment_deployment_path(@deployment)
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to start environment variables update: #{e.message}"
      
      respond_to do |format|
        format.json do
          render json: {
            success: false,
            message: "Failed to start environment variables update: #{e.message}"
          }
        end
        format.html do
          toast_error("Failed to start environment variables update: #{e.message}", title: "Update Failed")
          redirect_to manage_environment_deployment_path(@deployment)
        end
      end
    end
  end

  def check_ssl_status
    Rails.logger.info "=== SSL STATUS CHECK METHOD CALLED ==="
    Rails.logger.info "SSL status check requested for domain: #{params[:domain]} on deployment: #{@deployment.uuid}"
    
    begin
      domain_name = params[:domain]
      
      if domain_name.blank?
        Rails.logger.error "SSL check failed: Domain name is required"
        respond_to do |format|
          format.json { 
            render json: { success: false, error: "Domain name is required" }, 
                   status: :bad_request, content_type: 'application/json'
          }
        end
        return
      end
      
      # Find the domain
      domain = @deployment.domains.find_by(name: domain_name)
      
      unless domain
        Rails.logger.error "SSL check failed: Domain '#{domain_name}' not found"
        respond_to do |format|
          format.json { 
            render json: { success: false, error: "Domain not found" }, 
                   status: :not_found, content_type: 'application/json'
          }
        end
        return
      end
      
      Rails.logger.info "Running SSL verification for domain: #{domain_name}"
      
      # Clear any cached SSL verification and run fresh check
      domain.clear_ssl_verification_cache
      ssl_result = domain.verify_ssl_status
      
      Rails.logger.info "SSL verification completed for #{domain_name}: #{domain.real_ssl_status_text}"
      
      # Log the SSL check activity
      log_activity('ssl_status_checked', 
                  details: "Checked SSL status for domain: #{domain_name} - Status: #{domain.real_ssl_status_text}")
      
      # Return the result in the format expected by the JavaScript
      response_data = {
        success: true,
        ssl_status: {
          domain: domain_name,
          status_text: domain.real_ssl_status_text,
          status_color: domain.real_ssl_status_color,
          status_icon: domain.real_ssl_status_icon,
          ssl_active: domain.ssl_actually_working?,
          ssl_valid: domain.ssl_certificate_valid?,
          response_time: domain.ssl_response_time,
          error_message: domain.ssl_verification_error,
          certificate_info: domain.ssl_certificate_info,
          checked_at: domain.last_ssl_check_time&.iso8601
        }
      }
      
      Rails.logger.info "Returning SSL status response: #{response_data.to_json}"
      
      respond_to do |format|
        format.json { render json: response_data, content_type: 'application/json' }
      end
      
    rescue StandardError => e
      Rails.logger.error "SSL status check failed for domain #{params[:domain]}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      respond_to do |format|
        format.json { 
          render json: {
            success: false,
            error: "SSL check failed: #{e.message}"
          }, status: :internal_server_error, content_type: 'application/json'
        }
      end
    end
  end

  def git_configuration
    @github_linked_account = current_user.linked_accounts.find_by(provider: 'github')
    @github_repositories = []
    
    if @github_linked_account&.connected?
      begin
        github_service = GitHubService.new(@github_linked_account)
        result = github_service.get_repositories
        @github_repositories = result[:repositories] if result[:success]
      rescue => e
        Rails.logger.error "Failed to fetch GitHub repositories: #{e.message}"
        flash[:warning] = "Unable to fetch GitHub repositories. Please check your connection."
      end
    end
    
    log_activity('git_configuration_viewed', details: "Viewed Git configuration for deployment: #{@deployment.display_name}")
  end

  def update_git_configuration
    deployment_method = params[:deployment_method]
    
    case deployment_method
    when 'manual'
      @deployment.update!(
        deployment_method: 'manual',
        repository_url: nil,
        repository_branch: nil
      )
      toast_success("Git configuration updated to manual deployment.", title: "Configuration Updated")
      
    when 'github_repo'
      repository_url = params[:github_repository_url]
      branch = params[:repository_branch].presence || 'main'
      
      @deployment.update!(
        deployment_method: 'github_repo',
        repository_url: repository_url,
        repository_branch: branch
      )
      toast_success("GitHub repository configured successfully.", title: "Configuration Updated")
      
    when 'public_repo'
      repository_url = params[:public_repository_url]
      branch = params[:repository_branch].presence || 'main'
      
      @deployment.update!(
        deployment_method: 'public_repo',
        repository_url: repository_url,
        repository_branch: branch
      )
      toast_success("Public repository configured successfully.", title: "Configuration Updated")
    end
    
    log_activity('git_configuration_updated', 
                details: "Updated Git configuration for deployment: #{@deployment.display_name} - Method: #{deployment_method}")
    
    redirect_to @deployment
  rescue => e
    toast_error("Failed to update Git configuration: #{e.message}", title: "Configuration Failed")
    redirect_to git_configuration_deployment_path(@deployment)
  end

  def deploy
    unless @deployment.can_deploy?
      toast_error("Deployment not ready. Ensure server has Dokku installed and is connected.", title: "Deployment Failed")
      redirect_to @deployment
      return
    end

    unless @deployment.deployment_configured?
      toast_error("Git configuration required before deployment.", title: "Configuration Required")
      redirect_to git_configuration_deployment_path(@deployment)
      return
    end

    # Start deployment in background
    @deployment.update!(deployment_status: 'deploying')
    DeploymentJob.perform_later(@deployment)
    
    log_activity('deployment_started', details: "Started deployment for: #{@deployment.display_name}")
    toast_success("Deployment started! You can monitor progress in the logs.", title: "Deployment Started")
    redirect_to logs_deployment_path(@deployment)
  end

  def logs
    # This will show deployment logs in real-time
    log_activity('deployment_logs_viewed', details: "Viewed deployment logs for: #{@deployment.display_name}")
    
    respond_to do |format|
      format.html
      format.json do
        render json: {
          logs: @deployment.deployment_logs || "No logs available",
          status: @deployment.deployment_status || "pending",
          status_text: @deployment.status_text,
          status_icon: @deployment.status_icon,
          status_badge_class: @deployment.status_badge_class,
          last_deployment_at: @deployment.last_deployment_at&.strftime("%Y-%m-%d %H:%M:%S"),
          deployment_configured: @deployment.deployment_configured?,
          can_deploy: @deployment.can_deploy?
        }, status: 200, content_type: 'application/json'
      end
    end
  end

  private

  def set_deployment
    @deployment = current_user.deployments.find_by!(uuid: params[:uuid])
  rescue ActiveRecord::RecordNotFound
    toast_error("Deployment not found.", title: "Not Found")
    redirect_to deployments_path
  end
  
  def authorize_deployment
    authorize @deployment
  end

  def deployment_params
    params.require(:deployment).permit(:name, :description, :server_id)
  end

end
