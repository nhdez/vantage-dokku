class Deployments::DatabasesController < Deployments::BaseController
  def configure_databases
    @database_configuration = @deployment.database_configuration || @deployment.build_database_configuration
    @available_databases = DatabaseConfiguration::SUPPORTED_DATABASES
    @redis_config = DatabaseConfiguration::REDIS_CONFIG

    sync_database_urls_to_environment_variables if @database_configuration.persisted? && @database_configuration.configured?

    @has_conflicts = @database_configuration.has_environment_variable_conflict?.any?

    log_activity("database_configuration_viewed", details: "Viewed database configuration for deployment: #{@deployment.display_name}")
  end

  def update_database_configuration
    database_hash = (params[:database_configuration] || {}).to_unsafe_h

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
      format.json { render json: { success: false, message: "Failed to start database configuration: #{e.message}" } }
      format.html do
        toast_error("Failed to start database configuration: #{e.message}", title: "Configuration Failed")
        redirect_to configure_databases_deployment_path(@deployment)
      end
    end
  end

  def delete_database_configuration
    @database_configuration = @deployment.database_configuration

    if @database_configuration.nil?
      respond_to do |format|
        format.html do
          toast_error("No database configuration found to delete", title: "Not Found")
          redirect_to configure_databases_deployment_path(@deployment)
        end
        format.json { render json: { success: false, message: "No database configuration found to delete" }, status: :not_found }
      end
      return
    end

    unless @database_configuration.can_be_deleted?
      respond_to do |format|
        format.html do
          toast_error("Database configuration cannot be deleted in its current state", title: "Cannot Delete")
          redirect_to configure_databases_deployment_path(@deployment)
        end
        format.json { render json: { success: false, message: "Database configuration cannot be deleted in its current state" }, status: :unprocessable_entity }
      end
      return
    end

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
      format.json { render json: { success: false, message: "An unexpected error occurred: #{e.message}" }, status: :internal_server_error }
    end
  end

  private

  def sync_database_urls_to_environment_variables
    Rails.logger.info "[DatabasesController] Syncing database URLs for deployment #{@deployment.uuid}"

    return unless @database_configuration.configured?

    service = SshConnectionService.new(@deployment.server)
    result = service.get_dokku_config(@deployment.dokku_app_name)

    unless result[:success] && result[:config].present?
      Rails.logger.warn "[DatabasesController] Failed to get Dokku config: #{result[:error]}"
      return
    end

    dokku_config = result[:config]

    sync_env_var(dokku_config, @database_configuration.environment_variable_name,
                 :database_url)

    if @database_configuration.redis_enabled?
      sync_env_var(dokku_config, @database_configuration.redis_environment_variable_name,
                   :redis_url)
    end
  rescue StandardError => e
    Rails.logger.error "[DatabasesController] Failed to sync database URLs from Dokku: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  def sync_env_var(dokku_config, env_var_name, config_attr)
    return unless env_var_name && dokku_config[env_var_name].present?

    value_from_dokku = dokku_config[env_var_name]

    if @database_configuration.send(config_attr) != value_from_dokku
      @database_configuration.update_columns(config_attr => value_from_dokku)
    end

    existing = @deployment.environment_variables.find_by(key: env_var_name)
    if existing.nil?
      @deployment.environment_variables.create!(key: env_var_name, value: value_from_dokku, source: "system")
    elsif existing.value != value_from_dokku
      existing.update!(value: value_from_dokku, source: "system")
    end
  end
end
