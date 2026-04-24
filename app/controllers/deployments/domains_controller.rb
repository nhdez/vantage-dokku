class Deployments::DomainsController < Deployments::BaseController
  def configure_domain
    @domains = @deployment.domains.ordered
    log_activity("domains_viewed", details: "Viewed domain configuration for deployment: #{@deployment.display_name}")
  end

  def update_domains
    domains_params = params[:domains] || {}
    domains_hash = domains_params.to_unsafe_h

    UpdateDomainsJob.perform_later(@deployment.id, current_user.id, domains_hash)

    log_activity("domains_update_started",
                details: "Started domain update for deployment: #{@deployment.display_name}")

    respond_to do |format|
      format.json do
        render json: {
          success: true,
          message: "Domain update started in background. You'll be notified when complete.",
          deployment_uuid: @deployment.uuid
        }
      end
      format.html do
        toast_info("Domain update started. You'll be notified when complete.", title: "Update Started")
        redirect_to configure_domain_deployment_path(@deployment)
      end
    end
  rescue StandardError => e
    Rails.logger.error "Failed to start domain update: #{e.message}"

    respond_to do |format|
      format.json { render json: { success: false, message: "Failed to start domain update: #{e.message}" } }
      format.html do
        toast_error("Failed to start domain update: #{e.message}", title: "Update Failed")
        redirect_to configure_domain_deployment_path(@deployment)
      end
    end
  end

  def delete_domain
    domain_name = params[:domain_name]

    if domain_name.blank?
      respond_to do |format|
        format.json { render json: { success: false, error: "Domain name is required" }, status: :bad_request }
      end
      return
    end

    domain = @deployment.domains.find_by(name: domain_name)

    unless domain
      respond_to do |format|
        format.json { render json: { success: false, error: "Domain not found" }, status: :not_found }
      end
      return
    end

    DeleteDomainJob.perform_later(@deployment.id, domain.id, current_user.id)

    log_activity("domain_deletion_started",
                details: "Started deletion of domain #{domain_name} from deployment: #{@deployment.display_name}")

    respond_to do |format|
      format.json do
        render json: {
          success: true,
          message: "Domain deletion started. SSL certificates will be cleaned up.",
          domain_name: domain_name
        }
      end
    end
  rescue StandardError => e
    Rails.logger.error "Failed to delete domain: #{e.message}"

    respond_to do |format|
      format.json { render json: { success: false, error: "Failed to delete domain: #{e.message}" }, status: :internal_server_error }
    end
  end

  def check_ssl_status
    Rails.logger.info "SSL status check requested for domain: #{params[:domain]} on deployment: #{@deployment.uuid}"

    domain_name = params[:domain]

    if domain_name.blank?
      respond_to do |format|
        format.json { render json: { success: false, error: "Domain name is required" }, status: :bad_request, content_type: "application/json" }
      end
      return
    end

    domain = @deployment.domains.find_by(name: domain_name)

    unless domain
      respond_to do |format|
        format.json { render json: { success: false, error: "Domain not found" }, status: :not_found, content_type: "application/json" }
      end
      return
    end

    domain.clear_ssl_verification_cache
    domain.verify_ssl_status

    log_activity("ssl_status_checked",
                details: "Checked SSL status for domain: #{domain_name} - Status: #{domain.real_ssl_status_text}")

    respond_to do |format|
      format.json do
        render json: {
          success: true,
          ssl_status: {
            domain: domain_name,
            status_text: domain.real_ssl_status_text,
            status_color: domain.real_ssl_status_color,
            status_icon: domain.real_ssl_status_icon,
            ssl_active: domain.ssl_actually_working?,
            ssl_valid: domain.ssl_certificate_valid?,
            response_time: domain.ssl_response_time,
            error_message: domain.ssl_verification_error,
            certificate_info: domain.ssl_certificate_info,
            checked_at: domain.last_ssl_check_time&.iso8601
          }
        }, content_type: "application/json"
      end
    end
  rescue StandardError => e
    Rails.logger.error "SSL status check failed for domain #{params[:domain]}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    respond_to do |format|
      format.json { render json: { success: false, error: "SSL check failed: #{e.message}" }, status: :internal_server_error, content_type: "application/json" }
    end
  end
end
