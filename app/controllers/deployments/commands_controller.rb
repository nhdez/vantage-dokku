class Deployments::CommandsController < Deployments::BaseController
  def execute_commands
    log_activity("execute_commands_viewed", details: "Viewed execute commands interface for deployment: #{@deployment.display_name}")
  end

  def run_command
    command = params[:command]&.strip
    raw_command = params[:raw_command] == "1"

    if command.blank?
      respond_to do |format|
        format.json { render json: { success: false, message: "Command cannot be empty" } }
        format.html do
          toast_error("Command cannot be empty", title: "Invalid Command")
          redirect_to execute_commands_deployment_path(@deployment)
        end
      end
      return
    end

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
      format.json { render json: { success: false, message: "Failed to execute command: #{e.message}" } }
      format.html do
        toast_error("Failed to execute command: #{e.message}", title: "Execution Failed")
        redirect_to execute_commands_deployment_path(@deployment)
      end
    end
  end
end
