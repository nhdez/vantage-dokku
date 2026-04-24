class Deployments::ServerLogsController < Deployments::BaseController
  def server_logs
    log_activity("server_logs_viewed", details: "Viewed server logs interface for deployment: #{@deployment.display_name}")
  end

  def start_log_streaming
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
      format.json { render json: { success: false, message: "Failed to start server logs streaming: #{e.message}" } }
      format.html do
        toast_error("Failed to start server logs streaming: #{e.message}", title: "Streaming Failed")
        redirect_to server_logs_deployment_path(@deployment)
      end
    end
  end

  def stop_log_streaming
    ActionCable.server.broadcast("server_logs_#{@deployment.uuid}", {
      type: "stop_streaming",
      message: "Log streaming stopped by user"
    })

    log_activity("server_logs_streaming_stopped", details: "Stopped server logs streaming for deployment: #{@deployment.display_name}")

    respond_to do |format|
      format.json { render json: { success: true, message: "Server logs streaming stopped." } }
      format.html do
        toast_info("Server logs streaming stopped.", title: "Streaming Stopped")
        redirect_to server_logs_deployment_path(@deployment)
      end
    end
  end
end
