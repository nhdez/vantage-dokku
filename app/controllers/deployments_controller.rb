class DeploymentsController < ApplicationController
  include ActivityTrackable

  KAMAL_ACTIONS = %i[
    kamal_configuration update_kamal_configuration
    kamal_registry update_kamal_registry test_kamal_registry
    kamal_push_env
  ].freeze

  before_action :set_deployment, only: [ :show, :edit, :update, :destroy, :git_configuration, :update_git_configuration, :deploy, :logs, :configure_domain, :update_domains, :delete_domain, :attach_ssh_keys, :update_ssh_keys, :configure_databases, :update_database_configuration, :delete_database_configuration, :port_mappings, :sync_port_mappings, :add_port_mapping, :remove_port_mapping, :clear_port_mappings, :create_dokku_app, :manage_environment, :update_environment, :check_ssl_status, :execute_commands, :run_command, :server_logs, :start_log_streaming, :stop_log_streaming, :scans, :trigger_scan, *KAMAL_ACTIONS ]
  before_action :authorize_deployment, only: [ :show, :edit, :update, :destroy, :git_configuration, :update_git_configuration, :deploy, :logs, :configure_domain, :update_domains, :delete_domain, :attach_ssh_keys, :update_ssh_keys, :configure_databases, :update_database_configuration, :delete_database_configuration, :port_mappings, :sync_port_mappings, :add_port_mapping, :remove_port_mapping, :clear_port_mappings, :create_dokku_app, :manage_environment, :update_environment, :check_ssl_status, :execute_commands, :run_command, :server_logs, :start_log_streaming, :stop_log_streaming, :scans, :trigger_scan, *KAMAL_ACTIONS ]

  def index
    @pagy, @deployments = pagy(current_user.deployments.includes(:server).recent, limit: 15)
    log_activity("deployments_list_viewed", details: "Viewed deployments list (#{@deployments.count} deployments)")
  end

  def show
    @latest_vulnerability_scan = @deployment.vulnerability_scans.completed.recent.first
    log_activity("deployment_viewed", details: "Viewed deployment: #{@deployment.display_name}")
  end

  def new
    @deployment = current_user.deployments.build
    @dokku_servers = current_user.servers.where.not(dokku_version: [ nil, "" ])
    @kamal_servers = current_user.servers.connected
    authorize @deployment

    if @dokku_servers.empty? && @kamal_servers.empty?
      toast_error("You need at least one configured server to create a deployment.", title: "No Servers")
      redirect_to deployments_path
    end
  end

  def create
    @deployment = current_user.deployments.build(deployment_params)
    @dokku_servers = current_user.servers.where.not(dokku_version: [ nil, "" ])
    @kamal_servers = current_user.servers.connected
    authorize @deployment

    if @deployment.save
      log_activity("deployment_created", details: "Created deployment: #{@deployment.display_name} (#{@deployment.deployment_method_text})")
      if @deployment.kamal?
        toast_success("Kamal app '#{@deployment.name}' created! Configure your deployment settings below.", title: "App Created")
        redirect_to kamal_configuration_deployment_path(@deployment)
      else
        toast_success("Deployment '#{@deployment.name}' created successfully with Dokku app name '#{@deployment.dokku_app_name}'!", title: "Deployment Created")
        redirect_to @deployment
      end
    else
      toast_error("Failed to create deployment. Please check the form for errors.", title: "Creation Failed")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @available_servers = current_user.servers.where.not(dokku_version: [ nil, "" ])
    # Include current server even if it no longer has Dokku (for editing existing deployments)
    @available_servers = @available_servers.or(Server.where(id: @deployment.server_id))
  end

  def update
    @available_servers = current_user.servers.where.not(dokku_version: [ nil, "" ])
    @available_servers = @available_servers.or(Server.where(id: @deployment.server_id))

    if @deployment.update(deployment_params)
      log_activity("deployment_updated", details: "Updated deployment: #{@deployment.display_name}")
      toast_success("Deployment '#{@deployment.name}' updated successfully!", title: "Deployment Updated")
      redirect_to @deployment
    else
      toast_error("Failed to update deployment. Please check the form for errors.", title: "Update Failed")
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    deployment_name = @deployment.name

    # Queue the deletion job to run in background
    DestroyDeploymentJob.perform_later(@deployment.id, current_user.id)

    log_activity("deployment_deletion_started",
                details: "Started deletion of deployment: #{deployment_name}")

    respond_to do |format|
      format.html do
        toast_info("Deployment deletion started. The app will be removed from the server.", title: "Deletion Started")
        redirect_to deployments_path
      end

      format.json do
        render json: {
          success: true,
          message: "Deployment deletion started. The app will be removed from the server.",
          deployment_id: @deployment.id
        }
      end
      format.any do
        # Fallback for when Accept header is */*, which happens with some AJAX requests
        render json: {
          success: true,
          message: "Deployment deletion started. The app will be removed from the server.",
          deployment_id: @deployment.id
        }
      end
    end
  rescue StandardError => e
    Rails.logger.error "Failed to start deployment deletion: #{e.message}"

    respond_to do |format|
      format.html do
        toast_error("Failed to delete deployment: #{e.message}", title: "Deletion Error")
        redirect_to deployments_path
      end

      format.json do
        render json: {
          success: false,
          message: "Failed to delete deployment: #{e.message}"
        }, status: :internal_server_error
      end
    end
  end

  def create_dokku_app
    begin
      service = SshConnectionService.new(@deployment.server)
      result = service.create_dokku_app(@deployment.dokku_app_name)

      if result[:success]
        log_activity("dokku_app_created", details: "Created Dokku app: #{@deployment.dokku_app_name} on server: #{@deployment.server.name}")
        toast_success("Dokku app '#{@deployment.dokku_app_name}' created successfully!", title: "App Created")
        # Update deployment status here in future
      else
        log_activity("dokku_app_creation_failed", details: "Failed to create Dokku app: #{@deployment.dokku_app_name} - #{result[:error]}")
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
    log_activity("domains_viewed", details: "Viewed domain configuration for deployment: #{@deployment.display_name}")
  end

  def delete_domain
    begin
      domain_name = params[:domain_name]

      if domain_name.blank?
        respond_to do |format|
          format.json { render json: { success: false, error: "Domain name is required" }, status: :bad_request }
        end
        return
      end

      # Find and verify the domain belongs to this deployment
      domain = @deployment.domains.find_by(name: domain_name)

      unless domain
        respond_to do |format|
          format.json { render json: { success: false, error: "Domain not found" }, status: :not_found }
        end
        return
      end

      # Remove domain from Dokku and clean up SSL
      DeleteDomainJob.perform_later(@deployment.id, domain.id, current_user.id)

      log_activity("domain_deletion_started",
                  details: "Started deletion of domain #{domain_name} from deployment: #{@deployment.display_name}")

      respond_to do |format|
        format.json do
          render json: {
            success: true,
            message: "Domain deletion started. SSL certificates will be cleaned up.",
            domain_name: domain_name
          }
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to delete domain: #{e.message}"

      respond_to do |format|
        format.json do
          render json: {
            success: false,
            error: "Failed to delete domain: #{e.message}"
          }, status: :internal_server_error
        end
      end
    end
  end

  def update_domains
    begin
      domains_params = params[:domains] || {}

      # Convert parameters to a serializable hash for the job
      domains_hash = domains_params.to_unsafe_h

      # Start the domains update in the background
      UpdateDomainsJob.perform_later(@deployment.id, current_user.id, domains_hash)

      log_activity("domains_update_started",
                  details: "Started domain update for deployment: #{@deployment.display_name}")

      respond_to do |format|
        format.json do
          render json: {
            success: true,
            message: "Domain update started in background. You'll be notified when complete.",
            deployment_uuid: @deployment.uuid
          }
        end
        format.html do
          toast_info("Domain update started. You'll be notified when complete.", title: "Update Started")
          redirect_to configure_domain_deployment_path(@deployment)
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to start domain update: #{e.message}"

      respond_to do |format|
        format.json do
          render json: {
            success: false,
            message: "Failed to start domain update: #{e.message}"
          }
        end
        format.html do
          toast_error("Failed to start domain update: #{e.message}", title: "Update Failed")
          redirect_to configure_domain_deployment_path(@deployment)
        end
      end
    end
  end

  def attach_ssh_keys
    @available_ssh_keys = current_user.ssh_keys.active.order(:name)
    @attached_ssh_keys = @deployment.ssh_keys
    log_activity("ssh_keys_attachment_viewed", details: "Viewed SSH key attachment for deployment: #{@deployment.display_name}")
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

        log_activity("ssh_keys_updated", details: "Updated SSH keys for deployment: #{@deployment.display_name} - #{message_parts.join(', ')}")
        toast_success("SSH keys updated successfully! #{message_parts.join(', ').capitalize}.", title: "Keys Updated")
      else
        log_activity("ssh_keys_sync_failed", details: "Failed to sync SSH keys for deployment: #{@deployment.display_name} - #{result[:error]}")
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

    # Sync existing database URLs to EnvironmentVariables table if they exist but aren't synced
    # This helps with backwards compatibility for deployments that had databases configured before this feature
    sync_database_urls_to_environment_variables if @database_configuration.persisted? && @database_configuration.configured?

    # Check for environment variable conflicts
    @has_conflicts = @database_configuration.has_environment_variable_conflict?.any?

    log_activity("database_configuration_viewed", details: "Viewed database configuration for deployment: #{@deployment.display_name}")
  end

  def update_database_configuration
    begin
      database_params = params[:database_configuration] || {}

      # Convert parameters to a serializable hash for the job
      database_hash = database_params.to_unsafe_h

      # Start the database configuration in the background
      UpdateDatabaseConfigurationJob.perform_later(@deployment.id, current_user.id, database_hash)

      log_activity("database_configuration_started",
                  details: "Started database configuration for deployment: #{@deployment.display_name}")

      respond_to do |format|
        format.json do
          render json: {
            success: true,
            message: "Database configuration started in background. You'll be notified when complete.",
            deployment_uuid: @deployment.uuid
          }
        end
        format.html do
          toast_info("Database configuration started. You'll be notified when complete.", title: "Configuration Started")
          redirect_to configure_databases_deployment_path(@deployment)
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to start database configuration: #{e.message}"

      respond_to do |format|
        format.json do
          render json: {
            success: false,
            message: "Failed to start database configuration: #{e.message}"
          }
        end
        format.html do
          toast_error("Failed to start database configuration: #{e.message}", title: "Configuration Failed")
          redirect_to configure_databases_deployment_path(@deployment)
        end
      end
    end
  end

  def delete_database_configuration
    begin
      @database_configuration = @deployment.database_configuration

      if @database_configuration.nil?
        respond_to do |format|
          format.html do
            toast_error("No database configuration found to delete", title: "Not Found")
            redirect_to configure_databases_deployment_path(@deployment)
          end
          format.json do
            render json: { success: false, message: "No database configuration found to delete" }, status: :not_found
          end
        end
        return
      end

      unless @database_configuration.can_be_deleted?
        respond_to do |format|
          format.html do
            toast_error("Database configuration cannot be deleted in its current state", title: "Cannot Delete")
            redirect_to configure_databases_deployment_path(@deployment)
          end
          format.json do
            render json: { success: false, message: "Database configuration cannot be deleted in its current state" }, status: :unprocessable_entity
          end
        end
        return
      end

      # Queue the deletion job to run in background
      DeleteDatabaseConfigurationJob.perform_later(@deployment.id, current_user.id)

      log_activity("database_deletion_started",
                  details: "Started deletion of database configuration for deployment: #{@deployment.display_name}")

      respond_to do |format|
        format.html do
          toast_info("Database deletion started in background. You'll be notified when complete.", title: "Deletion Started")
          redirect_to configure_databases_deployment_path(@deployment)
        end
        format.json do
          render json: {
            success: true,
            message: "Database deletion started in background",
            redirect: configure_databases_deployment_path(@deployment)
          }, status: :ok
        end
      end

    rescue StandardError => e
      Rails.logger.error "Failed to start database deletion: #{e.message}"

      respond_to do |format|
        format.html do
          toast_error("An unexpected error occurred: #{e.message}", title: "Deletion Error")
          redirect_to configure_databases_deployment_path(@deployment)
        end
        format.json do
          render json: {
            success: false,
            message: "An unexpected error occurred: #{e.message}"
          }, status: :internal_server_error
        end
      end
    end
  end

  def port_mappings
    @port_mappings = @deployment.port_mappings.ordered

    # Sync port mappings from Dokku if none exist locally
    sync_port_mappings_from_dokku if @port_mappings.empty?

    # Reload after sync
    @port_mappings = @deployment.port_mappings.ordered

    log_activity("port_mappings_viewed", details: "Viewed port mappings for deployment: #{@deployment.display_name}")
  end

  def sync_port_mappings
    begin
      service = SshConnectionService.new(@deployment.server)
      result = service.list_ports(@deployment.dokku_app_name)

      if result[:success]
        # Sync port mappings to database
        sync_result = sync_port_mappings_to_database(result[:ports])

        respond_to do |format|
          format.json do
            render json: {
              success: true,
              message: "Port mappings synced successfully",
              port_mappings: @deployment.port_mappings.ordered.map { |pm|
                { id: pm.id, scheme: pm.scheme, host_port: pm.host_port, container_port: pm.container_port }
              }
            }
          end
          format.html do
            toast_success("Port mappings synced successfully", title: "Sync Complete")
            redirect_to port_mappings_deployment_path(@deployment)
          end
        end
      else
        respond_to do |format|
          format.json do
            render json: { success: false, message: result[:error] }, status: :unprocessable_entity
          end
          format.html do
            toast_error(result[:error], title: "Sync Failed")
            redirect_to port_mappings_deployment_path(@deployment)
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to sync port mappings: #{e.message}"

      respond_to do |format|
        format.json do
          render json: { success: false, message: e.message }, status: :internal_server_error
        end
        format.html do
          toast_error(e.message, title: "Sync Error")
          redirect_to port_mappings_deployment_path(@deployment)
        end
      end
    end
  end

  def add_port_mapping
    begin
      scheme = params[:scheme]
      host_port = params[:host_port].to_i
      container_port = params[:container_port].to_i

      # Add to Dokku first
      service = SshConnectionService.new(@deployment.server)
      result = service.add_port(@deployment.dokku_app_name, scheme, host_port, container_port)

      if result[:success]
        # Add to database
        port_mapping = @deployment.port_mappings.create!(
          scheme: scheme,
          host_port: host_port,
          container_port: container_port
        )

        log_activity("port_mapping_added",
                    details: "Added port mapping #{scheme}:#{host_port}:#{container_port} to deployment: #{@deployment.display_name}")

        respond_to do |format|
          format.json do
            render json: {
              success: true,
              message: "Port mapping added successfully",
              port_mapping: { id: port_mapping.id, scheme: port_mapping.scheme,
                             host_port: port_mapping.host_port, container_port: port_mapping.container_port }
            }
          end
          format.html do
            toast_success("Port mapping added successfully", title: "Port Added")
            redirect_to port_mappings_deployment_path(@deployment)
          end
        end
      else
        respond_to do |format|
          format.json do
            render json: { success: false, message: result[:error] }, status: :unprocessable_entity
          end
          format.html do
            toast_error(result[:error], title: "Add Failed")
            redirect_to port_mappings_deployment_path(@deployment)
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to add port mapping: #{e.message}"

      respond_to do |format|
        format.json do
          render json: { success: false, message: e.message }, status: :internal_server_error
        end
        format.html do
          toast_error(e.message, title: "Add Error")
          redirect_to port_mappings_deployment_path(@deployment)
        end
      end
    end
  end

  def remove_port_mapping
    begin
      port_mapping = @deployment.port_mappings.find(params[:port_mapping_id])

      # Remove from Dokku first
      service = SshConnectionService.new(@deployment.server)
      result = service.remove_port(@deployment.dokku_app_name, port_mapping.scheme,
                                   port_mapping.host_port, port_mapping.container_port)

      if result[:success]
        # Remove from database
        port_mapping.destroy!

        log_activity("port_mapping_removed",
                    details: "Removed port mapping #{port_mapping.display_name} from deployment: #{@deployment.display_name}")

        respond_to do |format|
          format.json do
            render json: { success: true, message: "Port mapping removed successfully" }
          end
          format.html do
            toast_success("Port mapping removed successfully", title: "Port Removed")
            redirect_to port_mappings_deployment_path(@deployment)
          end
        end
      else
        respond_to do |format|
          format.json do
            render json: { success: false, message: result[:error] }, status: :unprocessable_entity
          end
          format.html do
            toast_error(result[:error], title: "Remove Failed")
            redirect_to port_mappings_deployment_path(@deployment)
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to remove port mapping: #{e.message}"

      respond_to do |format|
        format.json do
          render json: { success: false, message: e.message }, status: :internal_server_error
        end
        format.html do
          toast_error(e.message, title: "Remove Error")
          redirect_to port_mappings_deployment_path(@deployment)
        end
      end
    end
  end

  def clear_port_mappings
    begin
      # Clear from Dokku first
      service = SshConnectionService.new(@deployment.server)
      result = service.clear_ports(@deployment.dokku_app_name)

      if result[:success]
        # Clear from database
        @deployment.port_mappings.destroy_all

        log_activity("port_mappings_cleared",
                    details: "Cleared all port mappings for deployment: #{@deployment.display_name}")

        respond_to do |format|
          format.json do
            render json: { success: true, message: "All port mappings cleared successfully" }
          end
          format.html do
            toast_success("All port mappings cleared successfully", title: "Ports Cleared")
            redirect_to port_mappings_deployment_path(@deployment)
          end
        end
      else
        respond_to do |format|
          format.json do
            render json: { success: false, message: result[:error] }, status: :unprocessable_entity
          end
          format.html do
            toast_error(result[:error], title: "Clear Failed")
            redirect_to port_mappings_deployment_path(@deployment)
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to clear port mappings: #{e.message}"

      respond_to do |format|
        format.json do
          render json: { success: false, message: e.message }, status: :internal_server_error
        end
        format.html do
          toast_error(e.message, title: "Clear Error")
          redirect_to port_mappings_deployment_path(@deployment)
        end
      end
    end
  end

  def manage_environment
    @environment_variables = @deployment.environment_variables.ordered
    log_activity("environment_variables_viewed", details: "Viewed environment variables for deployment: #{@deployment.display_name}")
  end

  def update_environment
    begin
      env_vars_params = params[:environment_variables] || {}

      # Convert parameters to a serializable hash for the job
      env_vars_hash = env_vars_params.to_unsafe_h

      # Persist the `secret` flag for Kamal deployments directly in the DB
      if @deployment.kamal?
        env_vars_hash.each_value do |attrs|
          next unless attrs["key"].present?
          ev = @deployment.environment_variables.find_by(key: attrs["key"])
          ev&.update_column(:secret, attrs["secret"].to_s == "1")
        end
      end

      # Start the environment variables update in the background
      UpdateEnvironmentJob.perform_later(@deployment.id, current_user.id, env_vars_hash)

      log_activity("environment_variables_update_started",
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
                   status: :bad_request, content_type: "application/json"
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
                   status: :not_found, content_type: "application/json"
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
      log_activity("ssl_status_checked",
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
        format.json { render json: response_data, content_type: "application/json" }
      end

    rescue StandardError => e
      Rails.logger.error "SSL status check failed for domain #{params[:domain]}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      respond_to do |format|
        format.json {
          render json: {
            success: false,
            error: "SSL check failed: #{e.message}"
          }, status: :internal_server_error, content_type: "application/json"
        }
      end
    end
  end

  def git_configuration
    @github_linked_account = current_user.linked_accounts.find_by(provider: "github")
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

    log_activity("git_configuration_viewed", details: "Viewed Git configuration for deployment: #{@deployment.display_name}")
  end

  def update_git_configuration
    deployment_method = params[:deployment_method]

    case deployment_method
    when "manual"
      @deployment.update!(
        deployment_method: "manual",
        repository_url: nil,
        repository_branch: nil
      )
      toast_success("Git configuration updated to manual deployment.", title: "Configuration Updated")

    when "github_repo"
      repository_url = params[:github_repository_url]
      branch = params[:repository_branch].presence || "main"

      @deployment.update!(
        deployment_method: "github_repo",
        repository_url: repository_url,
        repository_branch: branch
      )
      toast_success("GitHub repository configured successfully.", title: "Configuration Updated")

    when "public_repo"
      repository_url = params[:public_repository_url]
      branch = params[:repository_branch].presence || "main"

      @deployment.update!(
        deployment_method: "public_repo",
        repository_url: repository_url,
        repository_branch: branch
      )
      toast_success("Public repository configured successfully.", title: "Configuration Updated")
    end

    log_activity("git_configuration_updated",
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
    @deployment.update!(deployment_status: "deploying")
    DeploymentJob.perform_later(@deployment)

    log_activity("deployment_started", details: "Started deployment for: #{@deployment.display_name}")
    toast_success("Deployment started! You can monitor progress in the logs.", title: "Deployment Started")
    redirect_to logs_deployment_path(@deployment)
  end

  def logs
    # This will show deployment logs in real-time
    log_activity("deployment_logs_viewed", details: "Viewed deployment logs for: #{@deployment.display_name}")

    respond_to do |format|
      format.html
      format.json do
        latest_attempt = @deployment.latest_deployment_attempt

        render json: {
          logs: latest_attempt&.logs || "No logs available",
          status: @deployment.deployment_status || "pending",
          status_text: @deployment.status_text,
          status_icon: @deployment.status_icon,
          status_badge_class: @deployment.status_badge_class,
          last_deployment_at: @deployment.last_deployment_at&.strftime("%Y-%m-%d %H:%M:%S"),
          deployment_configured: @deployment.deployment_configured?,
          can_deploy: @deployment.can_deploy?,
          latest_attempt: latest_attempt ? {
            id: latest_attempt.id,
            attempt_number: latest_attempt.attempt_number,
            status: latest_attempt.status,
            logs: latest_attempt.logs,
            started_at: latest_attempt.started_at&.strftime("%Y-%m-%d %H:%M:%S"),
            completed_at: latest_attempt.completed_at&.strftime("%Y-%m-%d %H:%M:%S"),
            duration_text: latest_attempt.duration_text,
            error_message: latest_attempt.error_message
          } : nil
        }, status: 200, content_type: "application/json"
      end
    end
  end

  def execute_commands
    # Show the execute commands interface
    log_activity("execute_commands_viewed", details: "Viewed execute commands interface for deployment: #{@deployment.display_name}")
  end

  def run_command
    command = params[:command]&.strip
    raw_command = params[:raw_command] == "1"

    if command.blank?
      respond_to do |format|
        format.json do
          render json: {
            success: false,
            message: "Command cannot be empty"
          }
        end
        format.html do
          toast_error("Command cannot be empty", title: "Invalid Command")
          redirect_to execute_commands_deployment_path(@deployment)
        end
      end
      return
    end

    # Start command execution in background
    ExecuteCommandJob.perform_later(@deployment, current_user, command, raw_command)

    log_activity("command_executed", details: "Executed command '#{command}' on deployment: #{@deployment.display_name}")

    respond_to do |format|
      format.json do
        render json: {
          success: true,
          message: "Command execution started in background. You'll see output in real-time below.",
          deployment_uuid: @deployment.uuid,
          command: command
        }
      end
      format.html do
        toast_info("Command execution started. You'll see output in real-time below.", title: "Command Started")
        redirect_to execute_commands_deployment_path(@deployment)
      end
    end
  rescue StandardError => e
    Rails.logger.error "Failed to execute command: #{e.message}"

    respond_to do |format|
      format.json do
        render json: {
          success: false,
          message: "Failed to execute command: #{e.message}"
        }
      end
      format.html do
        toast_error("Failed to execute command: #{e.message}", title: "Execution Failed")
        redirect_to execute_commands_deployment_path(@deployment)
      end
    end
  end

  def server_logs
    # Show the server logs interface
    log_activity("server_logs_viewed", details: "Viewed server logs interface for deployment: #{@deployment.display_name}")
  end

  def start_log_streaming
    # Start streaming server logs in background
    ServerLogsStreamingJob.perform_later(@deployment, current_user)

    log_activity("server_logs_streaming_started", details: "Started server logs streaming for deployment: #{@deployment.display_name}")

    respond_to do |format|
      format.json do
        render json: {
          success: true,
          message: "Server logs streaming started. You'll see live output below.",
          deployment_uuid: @deployment.uuid
        }
      end
      format.html do
        toast_info("Server logs streaming started. You'll see live output below.", title: "Streaming Started")
        redirect_to server_logs_deployment_path(@deployment)
      end
    end
  rescue StandardError => e
    Rails.logger.error "Failed to start server logs streaming: #{e.message}"

    respond_to do |format|
      format.json do
        render json: {
          success: false,
          message: "Failed to start server logs streaming: #{e.message}"
        }
      end
      format.html do
        toast_error("Failed to start server logs streaming: #{e.message}", title: "Streaming Failed")
        redirect_to server_logs_deployment_path(@deployment)
      end
    end
  end

  def stop_log_streaming
    # Stop streaming server logs
    # We'll broadcast a stop signal to the streaming job
    ActionCable.server.broadcast("server_logs_#{@deployment.uuid}", {
      type: "stop_streaming",
      message: "Log streaming stopped by user"
    })

    log_activity("server_logs_streaming_stopped", details: "Stopped server logs streaming for deployment: #{@deployment.display_name}")

    respond_to do |format|
      format.json do
        render json: {
          success: true,
          message: "Server logs streaming stopped."
        }
      end
      format.html do
        toast_info("Server logs streaming stopped.", title: "Streaming Stopped")
        redirect_to server_logs_deployment_path(@deployment)
      end
    end
  end

  def scans
    @vulnerability_scans = @deployment.vulnerability_scans.includes(:vulnerabilities).recent
    @pagy, @vulnerability_scans = pagy(@vulnerability_scans, limit: 20)
    @latest_scan = @vulnerability_scans.first

    log_activity("vulnerability_scans_viewed", details: "Viewed vulnerability scans for deployment: #{@deployment.display_name}")
  end

  def trigger_scan
    begin
      # Check if OSV Scanner is installed on the server
      service = SshConnectionService.new(@deployment.server)
      osv_result = service.check_osv_scanner_version

      unless osv_result[:installed]
        respond_to do |format|
          format.json { render json: { success: false, message: "OSV Scanner is not installed on the server" }, status: :unprocessable_entity }
          format.html do
            toast_error("OSV Scanner must be installed on the server before scanning", title: "Scanner Not Installed")
            redirect_to scans_deployment_path(@deployment)
          end
        end
        return
      end

      # Check if a scan is already running
      if @deployment.vulnerability_scans.where(status: "running").exists?
        respond_to do |format|
          format.json { render json: { success: false, message: "A scan is already running for this deployment" }, status: :unprocessable_entity }
          format.html do
            toast_warning("A scan is already in progress", title: "Scan Running")
            redirect_to scans_deployment_path(@deployment)
          end
        end
        return
      end

      # Start scan in background
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          service.perform_vulnerability_scan(@deployment, "manual")
        end
      end

      log_activity("vulnerability_scan_triggered",
                  details: "Triggered manual vulnerability scan for deployment: #{@deployment.display_name}")

      respond_to do |format|
        format.json do
          render json: {
            success: true,
            message: "Vulnerability scan started. This may take a few minutes. Refresh the page to see results.",
            deployment_uuid: @deployment.uuid
          }
        end
        format.html do
          toast_success("Vulnerability scan started. Refresh the page in a few moments to see results.", title: "Scan Started")
          redirect_to scans_deployment_path(@deployment)
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to trigger vulnerability scan: #{e.message}"

      respond_to do |format|
        format.json { render json: { success: false, message: e.message }, status: :internal_server_error }
        format.html do
          toast_error(e.message, title: "Scan Error")
          redirect_to scans_deployment_path(@deployment)
        end
      end
    end
  end

  # ─── Kamal configuration (DAT-10) ──────────────────────────────────────────

  def kamal_configuration
    @kamal_config = @deployment.kamal_configuration || @deployment.create_kamal_configuration
    @available_servers = current_user.servers.connected.order(:name)
    @assigned_servers = @kamal_config.kamal_servers.includes(:server)
    log_activity("kamal_configuration_viewed", details: "Viewed Kamal configuration for: #{@deployment.display_name}")
  end

  def update_kamal_configuration
    @kamal_config = @deployment.kamal_configuration || @deployment.create_kamal_configuration

    if @kamal_config.update(kamal_configuration_params)
      sync_kamal_servers(@kamal_config, params[:kamal_server_assignments] || {})

      configured = @kamal_config.service_name.present? && @kamal_config.image.present? && @kamal_config.kamal_servers.web.any?
      @kamal_config.update!(configured: configured)

      log_activity("kamal_configuration_updated", details: "Updated Kamal configuration for: #{@deployment.display_name}")
      toast_success("Kamal configuration saved.", title: "Configuration Saved")
      redirect_to kamal_configuration_deployment_path(@deployment)
    else
      @available_servers = current_user.servers.connected.order(:name)
      @assigned_servers = @kamal_config.kamal_servers.includes(:server)
      toast_error("Failed to save configuration. Please check the form.", title: "Save Failed")
      render :kamal_configuration, status: :unprocessable_entity
    end
  end

  # ─── Kamal registry (DAT-11) ────────────────────────────────────────────────

  def kamal_registry
    @kamal_config = @deployment.kamal_configuration || @deployment.create_kamal_configuration
    @registry = @kamal_config.kamal_registry || @kamal_config.build_kamal_registry
    log_activity("kamal_registry_viewed", details: "Viewed registry configuration for: #{@deployment.display_name}")
  end

  def update_kamal_registry
    @kamal_config = @deployment.kamal_configuration || @deployment.create_kamal_configuration
    @registry = @kamal_config.kamal_registry || @kamal_config.build_kamal_registry

    registry_attrs = kamal_registry_params
    # Don't overwrite password if the placeholder was submitted
    registry_attrs.delete(:password) if registry_attrs[:password] == "••••••••"

    if @registry.update(registry_attrs)
      log_activity("kamal_registry_updated", details: "Updated registry credentials for: #{@deployment.display_name}")
      toast_success("Registry credentials saved.", title: "Registry Saved")
      redirect_to kamal_registry_deployment_path(@deployment)
    else
      toast_error("Failed to save registry credentials.", title: "Save Failed")
      render :kamal_registry, status: :unprocessable_entity
    end
  end

  def test_kamal_registry
    @kamal_config = @deployment.kamal_configuration
    registry = @kamal_config&.kamal_registry

    unless registry
      render json: { success: false, error: "Registry not configured" }, status: :unprocessable_entity
      return
    end

    result = test_registry_login(registry)
    render json: result
  end

  # ─── Kamal env push (DAT-12) ────────────────────────────────────────────────

  def kamal_push_env
    KamalEnvPushJob.perform_later(@deployment)
    log_activity("kamal_env_push_triggered", details: "Triggered env push for: #{@deployment.display_name}")
    toast_info("Pushing environment variables to servers...", title: "Env Push Started")
    redirect_to manage_environment_deployment_path(@deployment)
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
    params.require(:deployment).permit(:name, :description, :server_id, :deployment_method)
  end

  def kamal_configuration_params
    params.require(:kamal_configuration).permit(
      :service_name, :image,
      :builder_arch, :builder_remote,
      :asset_path, :healthcheck_path, :healthcheck_port,
      :proxy_host, :proxy_ssl, :proxy_app_port,
      :proxy_response_timeout, :proxy_buffering, :proxy_max_body_size, :proxy_forward_headers
    )
  end

  def kamal_registry_params
    params.require(:kamal_registry).permit(:registry_server, :username, :password)
  end

  # Sync KamalServer records from the servers assignment form.
  # params format: { "server_id" => { "role" => "web", "primary" => "1", "cmd" => "" } }
  def sync_kamal_servers(kamal_config, assignments)
    return unless assignments.is_a?(ActionController::Parameters) || assignments.is_a?(Hash)

    # Build the desired set of server_id+role pairs
    desired = assignments.to_unsafe_h.each_with_object([]) do |(server_id, attrs), arr|
      next unless attrs["role"].present?
      arr << {
        server_id: server_id.to_i,
        role: attrs["role"],
        primary: attrs["primary"].to_s == "1",
        cmd: attrs["cmd"].presence,
        stop_wait_time: attrs["stop_wait_time"].presence&.to_i,
        docker_options: {}
      }
    end

    desired_server_ids = desired.map { |d| d[:server_id] }

    # Remove assignments no longer in the form
    kamal_config.kamal_servers.where.not(server_id: desired_server_ids).destroy_all

    # Upsert each desired assignment
    desired.each do |attrs|
      ks = kamal_config.kamal_servers.find_or_initialize_by(server_id: attrs[:server_id], role: attrs[:role])
      ks.update!(attrs.except(:server_id, :role))
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn "[DeploymentsController] Could not assign server #{attrs[:server_id]}: #{e.message}"
    end
  end

  def test_registry_login(registry)
    require "open3"
    cmd = [ "docker", "login", registry.registry_server,
            "-u", registry.username, "--password-stdin" ]
    stdout, stderr, status = Open3.capture3(*cmd, stdin_data: registry.password)
    if status.success?
      { success: true, message: "Successfully authenticated with #{registry.registry_server}" }
    else
      { success: false, error: (stderr.presence || stdout).strip.truncate(200) }
    end
  rescue Errno::ENOENT
    { success: false, error: "Docker is not installed on the Vantage server" }
  rescue StandardError => e
    { success: false, error: e.message }
  end

  def sync_database_urls_to_environment_variables
    Rails.logger.info "[DeploymentsController] sync_database_urls_to_environment_variables called for deployment #{@deployment.uuid}"

    unless @database_configuration.configured?
      Rails.logger.info "[DeploymentsController] Database configuration not configured, skipping sync"
      return
    end

    Rails.logger.info "[DeploymentsController] Fetching Dokku config for app #{@deployment.dokku_app_name}"

    # Fetch actual config from Dokku server to get the real DATABASE_URL and REDIS_URL
    service = SshConnectionService.new(@deployment.server)
    result = service.get_dokku_config(@deployment.dokku_app_name)

    unless result[:success] && result[:config].present?
      Rails.logger.warn "[DeploymentsController] Failed to get Dokku config: #{result[:error]}"
      return
    end

    Rails.logger.info "[DeploymentsController] Successfully fetched Dokku config with #{result[:config].keys.count} variables"

    dokku_config = result[:config]
    database_url_from_dokku = nil
    redis_url_from_dokku = nil

    # Get the environment variable names based on database type
    db_env_var_name = @database_configuration.environment_variable_name
    redis_env_var_name = @database_configuration.redis_environment_variable_name if @database_configuration.redis_enabled?

    # Extract DATABASE_URL (or MONGO_URL) from Dokku config
    if db_env_var_name && dokku_config[db_env_var_name].present?
      database_url_from_dokku = dokku_config[db_env_var_name]

      # Update database_configuration if URL is missing or different
      # Use update_columns to skip validations (the conflict check would fail since we're about to create the env var)
      if @database_configuration.database_url != database_url_from_dokku
        @database_configuration.update_columns(database_url: database_url_from_dokku)
        Rails.logger.info "[DeploymentsController] Updated database_url in database_configuration for deployment #{@deployment.uuid}"
      end

      # Sync to EnvironmentVariables table if not present or different
      existing_var = @deployment.environment_variables.find_by(key: db_env_var_name)
      if existing_var.nil?
        @deployment.environment_variables.create!(
          key: db_env_var_name,
          value: database_url_from_dokku,
          source: "system"  # Mark as system-managed
        )
        Rails.logger.info "[DeploymentsController] Created #{db_env_var_name} in EnvironmentVariables for deployment #{@deployment.uuid}"
      elsif existing_var.value != database_url_from_dokku
        existing_var.update!(value: database_url_from_dokku, source: "system")
        Rails.logger.info "[DeploymentsController] Updated #{db_env_var_name} in EnvironmentVariables for deployment #{@deployment.uuid}"
      end
    end

    # Extract REDIS_URL from Dokku config if Redis is enabled
    if redis_env_var_name && dokku_config[redis_env_var_name].present?
      redis_url_from_dokku = dokku_config[redis_env_var_name]

      # Update database_configuration if URL is missing or different
      # Use update_columns to skip validations (the conflict check would fail since we're about to create the env var)
      if @database_configuration.redis_url != redis_url_from_dokku
        @database_configuration.update_columns(redis_url: redis_url_from_dokku)
        Rails.logger.info "[DeploymentsController] Updated redis_url in database_configuration for deployment #{@deployment.uuid}"
      end

      # Sync to EnvironmentVariables table if not present or different
      existing_redis_var = @deployment.environment_variables.find_by(key: redis_env_var_name)
      if existing_redis_var.nil?
        @deployment.environment_variables.create!(
          key: redis_env_var_name,
          value: redis_url_from_dokku,
          source: "system"  # Mark as system-managed
        )
        Rails.logger.info "[DeploymentsController] Created #{redis_env_var_name} in EnvironmentVariables for deployment #{@deployment.uuid}"
      elsif existing_redis_var.value != redis_url_from_dokku
        existing_redis_var.update!(value: redis_url_from_dokku, source: "system")
        Rails.logger.info "[DeploymentsController] Updated #{redis_env_var_name} in EnvironmentVariables for deployment #{@deployment.uuid}"
      end
    end
  rescue StandardError => e
    # Log the error but don't fail the page load
    Rails.logger.error "[DeploymentsController] Failed to sync database URLs from Dokku: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  def sync_port_mappings_from_dokku
    Rails.logger.info "[DeploymentsController] Syncing port mappings from Dokku for deployment #{@deployment.uuid}"

    service = SshConnectionService.new(@deployment.server)
    result = service.list_ports(@deployment.dokku_app_name)

    if result[:success] && result[:ports].any?
      sync_port_mappings_to_database(result[:ports])
      Rails.logger.info "[DeploymentsController] Successfully synced #{result[:ports].count} port mappings"
    else
      Rails.logger.info "[DeploymentsController] No port mappings found on Dokku or error occurred"
    end
  rescue StandardError => e
    # Log the error but don't fail the page load
    Rails.logger.error "[DeploymentsController] Failed to sync port mappings from Dokku: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  def sync_port_mappings_to_database(ports_from_dokku)
    ports_from_dokku.each do |port_data|
      @deployment.port_mappings.find_or_create_by!(
        scheme: port_data[:scheme],
        host_port: port_data[:host_port],
        container_port: port_data[:container_port]
      )
    end

    # Remove port mappings that no longer exist on Dokku
    existing_mappings = @deployment.port_mappings.all
    dokku_mapping_keys = ports_from_dokku.map { |p| "#{p[:scheme]}:#{p[:host_port]}:#{p[:container_port]}" }

    existing_mappings.each do |mapping|
      mapping_key = "#{mapping.scheme}:#{mapping.host_port}:#{mapping.container_port}"
      unless dokku_mapping_keys.include?(mapping_key)
        mapping.destroy!
        Rails.logger.info "[DeploymentsController] Removed stale port mapping: #{mapping_key}"
      end
    end
  end
end
