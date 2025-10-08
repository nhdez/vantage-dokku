class DeleteDatabaseConfigurationJob < ApplicationJob
  queue_as :default

  def perform(deployment_id, user_id)
    @deployment = Deployment.find(deployment_id)
    @user = User.find(user_id)
    @database_configuration = @deployment.database_configuration

    Rails.logger.info "[DeleteDatabaseConfigurationJob] Starting database deletion for deployment #{@deployment.uuid}"

    return unless @database_configuration

    begin
      # Get database details before deletion for logging
      db_name = @database_configuration.database_name
      redis_name = @database_configuration.redis_name if @database_configuration.redis_enabled?
      display_name = @database_configuration.display_name

      # Perform deletion on server
      service = SshConnectionService.new(@deployment.server)
      result = service.delete_database_configuration(@deployment.dokku_app_name, @database_configuration)

      if result[:success]
        # Delete the database configuration record
        @database_configuration.destroy!

        # Log the activity
        ActivityLog.create!(
          user: @user,
          action: 'database_deleted',
          details: "Deleted #{display_name} database configuration for deployment: #{@deployment.display_name}",
          occurred_at: Time.current
        )

        # Broadcast success via ActionCable (if you want real-time notification)
        ActionCable.server.broadcast("database_deletion_#{@deployment.uuid}", {
          type: 'success',
          message: "Database configuration deleted successfully! #{display_name} database (#{db_name})" +
                   (redis_name ? " and Redis instance (#{redis_name})" : "") +
                   " have been detached and deleted.",
          timestamp: Time.current.iso8601
        })

        Rails.logger.info "[DeleteDatabaseConfigurationJob] Database deletion completed successfully"
      else
        # Log the failure
        ActivityLog.create!(
          user: @user,
          action: 'database_deletion_failed',
          details: "Failed to delete database configuration for deployment: #{@deployment.display_name} - #{result[:error]}",
          occurred_at: Time.current
        )

        # Broadcast error via ActionCable
        ActionCable.server.broadcast("database_deletion_#{@deployment.uuid}", {
          type: 'error',
          message: "Failed to delete database: #{result[:error]}",
          timestamp: Time.current.iso8601
        })

        Rails.logger.error "[DeleteDatabaseConfigurationJob] Database deletion failed: #{result[:error]}"
      end

    rescue StandardError => e
      Rails.logger.error "[DeleteDatabaseConfigurationJob] Database deletion failed: #{e.message}"

      # Broadcast error
      ActionCable.server.broadcast("database_deletion_#{@deployment.uuid}", {
        type: 'error',
        message: "An unexpected error occurred: #{e.message}",
        timestamp: Time.current.iso8601
      })
    end
  end
end