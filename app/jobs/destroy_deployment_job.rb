class DestroyDeploymentJob < ApplicationJob
  queue_as :default

  def perform(deployment_id, user_id)
    @deployment = Deployment.find(deployment_id)
    @user = User.find(user_id)

    Rails.logger.info "[DestroyDeploymentJob] Starting deployment destruction for #{@deployment.name} (#{@deployment.dokku_app_name})"

    begin
      # Store deployment details before deletion
      deployment_name = @deployment.name
      dokku_app_name = @deployment.dokku_app_name
      server_name = @deployment.server.name

      # First, destroy the Dokku app on the server
      if @deployment.server.dokku_installed?
        Rails.logger.info "[DestroyDeploymentJob] Destroying Dokku app '#{dokku_app_name}' on server '#{server_name}'"

        service = SshConnectionService.new(@deployment.server)
        result = service.destroy_dokku_app(dokku_app_name)

        if result[:success]
          Rails.logger.info "[DestroyDeploymentJob] Successfully destroyed Dokku app on server"
        else
          Rails.logger.error "[DestroyDeploymentJob] Failed to destroy Dokku app on server: #{result[:error]}"
          # Continue with deletion even if server deletion fails (app might not exist on server)
        end
      else
        Rails.logger.info "[DestroyDeploymentJob] Skipping Dokku app destruction - Dokku not installed on server"
      end

      # Delete the deployment record and all associated records (cascading delete)
      @deployment.destroy!

      # Log the successful deletion
      ActivityLog.create!(
        user: @user,
        action: "deployment_deleted",
        details: "Deleted deployment '#{deployment_name}' (Dokku app: #{dokku_app_name}) from server '#{server_name}'",
        occurred_at: Time.current
      )

      # Broadcast success via ActionCable for real-time notification
      ActionCable.server.broadcast("deployment_deletion_#{@user.id}", {
        type: "success",
        deployment_id: deployment_id,
        message: "Deployment '#{deployment_name}' and its Dokku app have been successfully deleted from the server.",
        timestamp: Time.current.iso8601
      })

      Rails.logger.info "[DestroyDeploymentJob] Deployment deletion completed successfully"

    rescue StandardError => e
      Rails.logger.error "[DestroyDeploymentJob] Deployment deletion failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      # Log the failure
      ActivityLog.create!(
        user: @user,
        action: "deployment_deletion_failed",
        details: "Failed to delete deployment '#{@deployment.name}': #{e.message}",
        occurred_at: Time.current
      )

      # Broadcast error via ActionCable
      ActionCable.server.broadcast("deployment_deletion_#{@user.id}", {
        type: "error",
        deployment_id: deployment_id,
        message: "Failed to delete deployment: #{e.message}",
        timestamp: Time.current.iso8601
      })
    end
  end
end
