class ServersController < ApplicationController
  include ActivityTrackable
  
  before_action :set_server, only: [:show, :edit, :update, :destroy, :test_connection, :update_server, :install_dokku, :restart_server, :logs]
  before_action :authorize_server, only: [:show, :edit, :update, :destroy, :test_connection, :update_server, :install_dokku, :restart_server, :logs]
  
  def index
    @pagy, @servers = pagy(current_user.servers.order(:name), limit: 10)
    log_activity('server_list_viewed', details: "Viewed servers list (#{@servers.count} servers)")
  end

  def show
    log_activity('server_viewed', details: "Viewed server: #{@server.display_name}")
  end

  def new
    @server = current_user.servers.build(username: 'root', port: 22)
    authorize @server
  end

  def create
    @server = current_user.servers.build(server_params)
    authorize @server
    
    if @server.save
      log_activity('server_created', details: "Created server: #{@server.display_name}")
      toast_success("Server '#{@server.name}' created successfully!", title: "Server Created")
      redirect_to @server
    else
      toast_error("Failed to create server. Please check the form for errors.", title: "Creation Failed")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    # Server set by before_action
  end

  def update
    if @server.update(server_params)
      log_activity('server_updated', details: "Updated server: #{@server.display_name}")
      toast_success("Server '#{@server.name}' updated successfully!", title: "Server Updated")
      redirect_to @server
    else
      toast_error("Failed to update server. Please check the form for errors.", title: "Update Failed")
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    server_name = @server.name
    @server.destroy
    log_activity('server_deleted', details: "Deleted server: #{server_name}")
    toast_success("Server '#{server_name}' deleted successfully!", title: "Server Deleted")
    redirect_to servers_path
  end

  def test_connection
    begin
      service = SshConnectionService.new(@server)
      result = service.test_connection_and_gather_info
      
      if result[:success]
        log_activity('server_connection_tested', details: "Successfully connected to server: #{@server.display_name}")
        render json: {
          success: true,
          message: "Connection successful! Server information has been updated.",
          server_info: result[:server_info],
          connection_status: @server.reload.connection_status
        }
      else
        log_activity('server_connection_failed', details: "Failed to connect to server: #{@server.display_name} - #{result[:error]}")
        render json: {
          success: false,
          message: result[:error],
          connection_status: @server.reload.connection_status
        }
      end
    rescue StandardError => e
      Rails.logger.error "Connection test failed: #{e.message}"
      render json: {
        success: false,
        message: "An unexpected error occurred: #{e.message}",
        connection_status: 'failed'
      }
    end
  end

  def update_server
    begin
      service = SshConnectionService.new(@server)
      result = service.update_server_packages
      
      if result[:success]
        log_activity('server_updated', details: "Successfully updated packages on server: #{@server.display_name}")
        
        # Check if reboot is required
        reboot_required = result[:output].include?('REBOOT_REQUIRED')
        
        render json: {
          success: true,
          message: reboot_required ? 
            "Server updated successfully! A reboot is required to complete some updates." : 
            "Server updated successfully! All packages are up to date.",
          output: result[:output],
          reboot_required: reboot_required
        }
      else
        log_activity('server_update_failed', details: "Failed to update server: #{@server.display_name} - #{result[:error]}")
        render json: {
          success: false,
          message: result[:error],
          output: result[:output]
        }
      end
    rescue StandardError => e
      Rails.logger.error "Server update failed: #{e.message}"
      render json: {
        success: false,
        message: "An unexpected error occurred: #{e.message}"
      }
    end
  end

  def install_dokku
    begin
      service = SshConnectionService.new(@server)
      result = service.install_dokku_with_key_setup
      
      if result[:success]
        log_activity('dokku_installed', details: "Successfully installed Dokku on server: #{@server.display_name}")
        render json: {
          success: true,
          message: "Dokku installation completed successfully!",
          output: result[:output],
          dokku_installed: result[:dokku_installed]
        }
      else
        log_activity('dokku_installation_failed', details: "Failed to install Dokku on server: #{@server.display_name} - #{result[:error]}")
        render json: {
          success: false,
          message: result[:error],
          output: result[:output]
        }
      end
    rescue StandardError => e
      Rails.logger.error "Dokku installation failed: #{e.message}"
      render json: {
        success: false,
        message: "An unexpected error occurred: #{e.message}"
      }
    end
  end

  def restart_server
    begin
      service = SshConnectionService.new(@server)
      result = service.restart_server
      
      if result[:success]
        log_activity('server_restarted', details: "Successfully initiated restart on server: #{@server.display_name}")
        render json: {
          success: true,
          message: "Server restart initiated successfully! The server will be unavailable for a few minutes.",
          output: result[:output]
        }
      else
        log_activity('server_restart_failed', details: "Failed to restart server: #{@server.display_name} - #{result[:error]}")
        render json: {
          success: false,
          message: result[:error],
          output: result[:output]
        }
      end
    rescue StandardError => e
      Rails.logger.error "Server restart failed: #{e.message}"
      render json: {
        success: false,
        message: "An unexpected error occurred: #{e.message}"
      }
    end
  end

  def logs
    # Get activity logs related to this server
    # Search for server name and deployment names in the details field
    deployment_names = @server.deployments.pluck(:name)
    
    # Build a query to find logs that mention this server or its deployments
    search_terms = [@server.name, @server.display_name] + deployment_names
    search_conditions = search_terms.map { |term| "details ILIKE ?" }
    search_values = search_terms.map { |term| "%#{term}%" }
    
    @activity_logs = ActivityLog.includes(:user)
                               .where(search_conditions.join(' OR '), *search_values)
                               .order(occurred_at: :desc)
    
    @pagy, @activity_logs = pagy(@activity_logs, limit: 20)
    
    log_activity('server_logs_viewed', details: "Viewed activity logs for server: #{@server.display_name}")
  end

  private

  def set_server
    @server = current_user.servers.find_by!(uuid: params[:uuid])
  rescue ActiveRecord::RecordNotFound
    toast_error("Server not found.", title: "Not Found")
    redirect_to servers_path
  end
  
  def authorize_server
    authorize @server
  end

  def server_params
    params.require(:server).permit(:name, :ip, :username, :internal_ip, :port, :service_provider, :password)
  end
end
