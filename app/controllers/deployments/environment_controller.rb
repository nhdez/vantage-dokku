class Deployments::EnvironmentController < Deployments::BaseController
  def manage_environment
    @environment_variables = @deployment.environment_variables.ordered
    log_activity("environment_variables_viewed", details: "Viewed environment variables for deployment: #{@deployment.display_name}")
  end

  def update_environment
    env_vars_hash = (params[:environment_variables] || {}).to_unsafe_h

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
      format.json { render json: { success: false, message: "Failed to start environment variables update: #{e.message}" } }
      format.html do
        toast_error("Failed to start environment variables update: #{e.message}", title: "Update Failed")
        redirect_to manage_environment_deployment_path(@deployment)
      end
    end
  end
end
