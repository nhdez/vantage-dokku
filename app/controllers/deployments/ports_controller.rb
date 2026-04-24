class Deployments::PortsController < Deployments::BaseController
  def port_mappings
    sync_port_mappings_from_dokku if @deployment.port_mappings.empty?
    @port_mappings = @deployment.port_mappings.ordered
    log_activity("port_mappings_viewed", details: "Viewed port mappings for deployment: #{@deployment.display_name}")
  end

  def sync_port_mappings
    service = SshConnectionService.new(@deployment.server)
    result = service.list_ports(@deployment.dokku_app_name)

    if result[:success]
      sync_to_database(result[:ports])

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
        format.json { render json: { success: false, message: result[:error] }, status: :unprocessable_entity }
        format.html do
          toast_error(result[:error], title: "Sync Failed")
          redirect_to port_mappings_deployment_path(@deployment)
        end
      end
    end
  rescue StandardError => e
    Rails.logger.error "Failed to sync port mappings: #{e.message}"

    respond_to do |format|
      format.json { render json: { success: false, message: e.message }, status: :internal_server_error }
      format.html do
        toast_error(e.message, title: "Sync Error")
        redirect_to port_mappings_deployment_path(@deployment)
      end
    end
  end

  def add_port_mapping
    scheme = params[:scheme]
    host_port = params[:host_port].to_i
    container_port = params[:container_port].to_i

    service = SshConnectionService.new(@deployment.server)
    result = service.add_port(@deployment.dokku_app_name, scheme, host_port, container_port)

    if result[:success]
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
        format.json { render json: { success: false, message: result[:error] }, status: :unprocessable_entity }
        format.html do
          toast_error(result[:error], title: "Add Failed")
          redirect_to port_mappings_deployment_path(@deployment)
        end
      end
    end
  rescue StandardError => e
    Rails.logger.error "Failed to add port mapping: #{e.message}"

    respond_to do |format|
      format.json { render json: { success: false, message: e.message }, status: :internal_server_error }
      format.html do
        toast_error(e.message, title: "Add Error")
        redirect_to port_mappings_deployment_path(@deployment)
      end
    end
  end

  def remove_port_mapping
    port_mapping = @deployment.port_mappings.find(params[:port_mapping_id])

    service = SshConnectionService.new(@deployment.server)
    result = service.remove_port(@deployment.dokku_app_name, port_mapping.scheme,
                                 port_mapping.host_port, port_mapping.container_port)

    if result[:success]
      port_mapping.destroy!

      log_activity("port_mapping_removed",
                  details: "Removed port mapping #{port_mapping.display_name} from deployment: #{@deployment.display_name}")

      respond_to do |format|
        format.json { render json: { success: true, message: "Port mapping removed successfully" } }
        format.html do
          toast_success("Port mapping removed successfully", title: "Port Removed")
          redirect_to port_mappings_deployment_path(@deployment)
        end
      end
    else
      respond_to do |format|
        format.json { render json: { success: false, message: result[:error] }, status: :unprocessable_entity }
        format.html do
          toast_error(result[:error], title: "Remove Failed")
          redirect_to port_mappings_deployment_path(@deployment)
        end
      end
    end
  rescue StandardError => e
    Rails.logger.error "Failed to remove port mapping: #{e.message}"

    respond_to do |format|
      format.json { render json: { success: false, message: e.message }, status: :internal_server_error }
      format.html do
        toast_error(e.message, title: "Remove Error")
        redirect_to port_mappings_deployment_path(@deployment)
      end
    end
  end

  def clear_port_mappings
    service = SshConnectionService.new(@deployment.server)
    result = service.clear_ports(@deployment.dokku_app_name)

    if result[:success]
      @deployment.port_mappings.destroy_all

      log_activity("port_mappings_cleared",
                  details: "Cleared all port mappings for deployment: #{@deployment.display_name}")

      respond_to do |format|
        format.json { render json: { success: true, message: "All port mappings cleared successfully" } }
        format.html do
          toast_success("All port mappings cleared successfully", title: "Ports Cleared")
          redirect_to port_mappings_deployment_path(@deployment)
        end
      end
    else
      respond_to do |format|
        format.json { render json: { success: false, message: result[:error] }, status: :unprocessable_entity }
        format.html do
          toast_error(result[:error], title: "Clear Failed")
          redirect_to port_mappings_deployment_path(@deployment)
        end
      end
    end
  rescue StandardError => e
    Rails.logger.error "Failed to clear port mappings: #{e.message}"

    respond_to do |format|
      format.json { render json: { success: false, message: e.message }, status: :internal_server_error }
      format.html do
        toast_error(e.message, title: "Clear Error")
        redirect_to port_mappings_deployment_path(@deployment)
      end
    end
  end

  private

  def sync_port_mappings_from_dokku
    service = SshConnectionService.new(@deployment.server)
    result = service.list_ports(@deployment.dokku_app_name)

    sync_to_database(result[:ports]) if result[:success] && result[:ports].any?
  rescue StandardError => e
    Rails.logger.error "[PortsController] Failed to sync port mappings from Dokku: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end

  def sync_to_database(ports_from_dokku)
    ports_from_dokku.each do |port_data|
      @deployment.port_mappings.find_or_create_by!(
        scheme: port_data[:scheme],
        host_port: port_data[:host_port],
        container_port: port_data[:container_port]
      )
    end

    dokku_keys = ports_from_dokku.map { |p| "#{p[:scheme]}:#{p[:host_port]}:#{p[:container_port]}" }

    @deployment.port_mappings.each do |mapping|
      key = "#{mapping.scheme}:#{mapping.host_port}:#{mapping.container_port}"
      mapping.destroy! unless dokku_keys.include?(key)
    end
  end
end
