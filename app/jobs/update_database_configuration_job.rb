class UpdateDatabaseConfigurationJob < ApplicationJob
  queue_as :default

  def perform(deployment_id, user_id, database_params)
    @deployment = Deployment.find(deployment_id)
    @user = User.find(user_id)
    @database_params = database_params
    
    Rails.logger.info "[UpdateDatabaseConfigurationJob] Starting database configuration for deployment #{@deployment.uuid}"
    
    begin
      # Broadcast that configuration is starting
      broadcast_update("Starting database configuration...")
      
      @database_configuration = @deployment.database_configuration || @deployment.build_database_configuration
      
      # Set the parameters
      @database_configuration.assign_attributes(
        database_type: @database_params['database_type'],
        redis_enabled: @database_params['redis_enabled'] == '1'
      )
      
      if @database_configuration.save
        broadcast_update("Database configuration saved. Configuring on server...")
        
        # Configure database on server
        service = SshConnectionService.new(@deployment.server)
        result = service.configure_database(@deployment.dokku_app_name, @database_configuration)
        
        if result[:success]
          @database_configuration.update!(
            configured: true,
            configuration_output: result[:output],
            error_message: nil
          )
          
          success_message = "Database configured successfully! "
          success_message += "#{@database_configuration.display_name} (#{@database_configuration.database_name})"
          success_message += " and #{@database_configuration.redis_display_name}" if @database_configuration.redis_enabled?
          success_message += " are now available."
          
          broadcast_success(success_message)
          
          Rails.logger.info "[UpdateDatabaseConfigurationJob] Database configuration completed successfully"
        else
          @database_configuration.update!(
            configured: false,
            configuration_output: result[:output],
            error_message: result[:error]
          )
          
          broadcast_error("Failed to configure database: #{result[:error]}")
          Rails.logger.error "[UpdateDatabaseConfigurationJob] Database configuration failed: #{result[:error]}"
        end
      else
        error_message = "Failed to save database configuration: #{@database_configuration.errors.full_messages.join(', ')}"
        broadcast_error(error_message)
        Rails.logger.error "[UpdateDatabaseConfigurationJob] #{error_message}"
      end
      
    rescue StandardError => e
      Rails.logger.error "[UpdateDatabaseConfigurationJob] Database configuration failed: #{e.message}"
      broadcast_error("An unexpected error occurred: #{e.message}")
    end
  end

  private

  def broadcast_update(message)
    ActionCable.server.broadcast("database_configuration_#{@deployment.uuid}", {
      type: 'update',
      message: message,
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_success(message)
    ActionCable.server.broadcast("database_configuration_#{@deployment.uuid}", {
      type: 'success',
      message: message,
      timestamp: Time.current.iso8601
    })
  end

  def broadcast_error(message)
    ActionCable.server.broadcast("database_configuration_#{@deployment.uuid}", {
      type: 'error',
      message: message,
      timestamp: Time.current.iso8601
    })
  end
end