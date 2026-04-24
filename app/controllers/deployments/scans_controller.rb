class Deployments::ScansController < Deployments::BaseController
  def scans
    @pagy, @vulnerability_scans = pagy(
      @deployment.vulnerability_scans.includes(:vulnerabilities).recent,
      limit: 20
    )
    @latest_scan = @vulnerability_scans.first

    log_activity("vulnerability_scans_viewed", details: "Viewed vulnerability scans for deployment: #{@deployment.display_name}")
  end

  def trigger_scan
    service = SshConnectionService.new(@deployment.server)
    osv_result = service.check_osv_scanner_version

    unless osv_result[:installed]
      respond_to do |format|
        format.json { render json: { success: false, message: "OSV Scanner is not installed on the server" }, status: :unprocessable_entity }
        format.html do
          toast_error("OSV Scanner must be installed on the server before scanning", title: "Scanner Not Installed")
          redirect_to scans_deployment_path(@deployment)
        end
      end
      return
    end

    if @deployment.vulnerability_scans.where(status: "running").exists?
      respond_to do |format|
        format.json { render json: { success: false, message: "A scan is already running for this deployment" }, status: :unprocessable_entity }
        format.html do
          toast_warning("A scan is already in progress", title: "Scan Running")
          redirect_to scans_deployment_path(@deployment)
        end
      end
      return
    end

    Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        service.perform_vulnerability_scan(@deployment, "manual")
      end
    end

    log_activity("vulnerability_scan_triggered",
                details: "Triggered manual vulnerability scan for deployment: #{@deployment.display_name}")

    respond_to do |format|
      format.json do
        render json: {
          success: true,
          message: "Vulnerability scan started. This may take a few minutes. Refresh the page to see results.",
          deployment_uuid: @deployment.uuid
        }
      end
      format.html do
        toast_success("Vulnerability scan started. Refresh the page in a few moments to see results.", title: "Scan Started")
        redirect_to scans_deployment_path(@deployment)
      end
    end
  rescue StandardError => e
    Rails.logger.error "Failed to trigger vulnerability scan: #{e.message}"

    respond_to do |format|
      format.json { render json: { success: false, message: e.message }, status: :internal_server_error }
      format.html do
        toast_error(e.message, title: "Scan Error")
        redirect_to scans_deployment_path(@deployment)
      end
    end
  end
end
