class DeploymentsController < ApplicationController
  include ActivityTrackable

  before_action :set_deployment, only: [
    :show, :edit, :update, :destroy,
    :create_dokku_app,
    :git_configuration, :update_git_configuration,
    :deploy, :logs
  ]
  before_action :authorize_deployment, only: [
    :show, :edit, :update, :destroy,
    :create_dokku_app,
    :git_configuration, :update_git_configuration,
    :deploy, :logs
  ]

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
    @available_servers = current_user.servers.where.not(dokku_version: [ nil, "" ])
    authorize @deployment

    if @available_servers.empty?
      toast_error("You need at least one server with Dokku installed to create a deployment.", title: "No Dokku Servers")
      redirect_to deployments_path
    end
  end

  def create
    @deployment = current_user.deployments.build(deployment_params)
    @available_servers = current_user.servers.where.not(dokku_version: [ nil, "" ])
    authorize @deployment

    if @deployment.save
      log_activity("deployment_created", details: "Created deployment: #{@deployment.display_name}")
      toast_success("Deployment '#{@deployment.name}' created successfully with Dokku app name '#{@deployment.dokku_app_name}'!", title: "Deployment Created")
      redirect_to @deployment
    else
      toast_error("Failed to create deployment. Please check the form for errors.", title: "Creation Failed")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @available_servers = current_user.servers.where.not(dokku_version: [ nil, "" ])
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
        render json: { success: false, message: "Failed to delete deployment: #{e.message}" },
               status: :internal_server_error
      end
    end
  end

  def create_dokku_app
    service = SshConnectionService.new(@deployment.server)
    result = service.create_dokku_app(@deployment.dokku_app_name)

    if result[:success]
      log_activity("dokku_app_created", details: "Created Dokku app: #{@deployment.dokku_app_name} on server: #{@deployment.server.name}")
      toast_success("Dokku app '#{@deployment.dokku_app_name}' created successfully!", title: "App Created")
    else
      log_activity("dokku_app_creation_failed", details: "Failed to create Dokku app: #{@deployment.dokku_app_name} - #{result[:error]}")
      toast_error("Failed to create Dokku app: #{result[:error]}", title: "Creation Failed")
    end
  rescue StandardError => e
    Rails.logger.error "Dokku app creation failed: #{e.message}"
    toast_error("An unexpected error occurred: #{e.message}", title: "Creation Error")
  ensure
    redirect_to @deployment
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
      @deployment.update!(deployment_method: "manual", repository_url: nil, repository_branch: nil)
      toast_success("Git configuration updated to manual deployment.", title: "Configuration Updated")

    when "github_repo"
      @deployment.update!(
        deployment_method: "github_repo",
        repository_url: params[:github_repository_url],
        repository_branch: params[:repository_branch].presence || "main"
      )
      toast_success("GitHub repository configured successfully.", title: "Configuration Updated")

    when "public_repo"
      @deployment.update!(
        deployment_method: "public_repo",
        repository_url: params[:public_repository_url],
        repository_branch: params[:repository_branch].presence || "main"
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

    @deployment.update!(deployment_status: "deploying")
    DeploymentJob.perform_later(@deployment)

    log_activity("deployment_started", details: "Started deployment for: #{@deployment.display_name}")

    respond_to do |format|
      format.html do
        toast_success("Deployment started! You can monitor progress in the logs.", title: "Deployment Started")
        redirect_to logs_deployment_path(@deployment)
      end
      format.json do
        render json: { success: true, deployment_uuid: @deployment.uuid,
                       message: "Deployment started for #{@deployment.dokku_app_name}" }
      end
    end
  end

  def logs
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
