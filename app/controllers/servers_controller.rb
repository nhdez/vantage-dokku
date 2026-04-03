require "timeout"

class ServersController < ApplicationController
  include ActivityTrackable

  before_action :set_server, only: [ :show, :edit, :update, :destroy, :test_connection, :update_server, :install_dokku, :restart_server, :logs, :firewall_rules, :sync_firewall_rules, :enable_ufw, :disable_ufw, :add_firewall_rule, :remove_firewall_rule, :toggle_firewall_rule, :apply_firewall_rules, :vulnerability_scanner, :check_scanner_status, :install_go, :install_osv_scanner, :update_scan_config, :scan_all_deployments ]
  before_action :authorize_server, only: [ :show, :edit, :update, :destroy, :test_connection, :update_server, :install_dokku, :restart_server, :logs, :firewall_rules, :sync_firewall_rules, :enable_ufw, :disable_ufw, :add_firewall_rule, :remove_firewall_rule, :toggle_firewall_rule, :apply_firewall_rules, :vulnerability_scanner, :check_scanner_status, :install_go, :install_osv_scanner, :update_scan_config, :scan_all_deployments ]

  def index
    @pagy, @servers = pagy(current_user.servers.order(:name), limit: 10)
    log_activity("server_list_viewed", details: "Viewed servers list (#{@servers.count} servers)")
  end

  def show
    @deployments = @server.deployments.includes(:domains, :application_healths).order(:name)

    # Check server connectivity status without blocking the page load
    @server_status = check_server_status_safely

    log_activity("server_viewed", details: "Viewed server: #{@server.display_name}")
  end

  def new
    @server = current_user.servers.build(username: "root", port: 22)
    authorize @server
  end

  def create
    @server = current_user.servers.build(server_params)
    authorize @server

    if @server.save
      log_activity("server_created", details: "Created server: #{@server.display_name}")
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
      log_activity("server_updated", details: "Updated server: #{@server.display_name}")
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
    log_activity("server_deleted", details: "Deleted server: #{server_name}")
    toast_success("Server '#{server_name}' deleted successfully!", title: "Server Deleted")
    redirect_to servers_path
  end

  def test_connection
    begin
      # Start the connection test in the background
      TestConnectionJob.perform_later(@server.id, current_user.id)

      log_activity("server_connection_test_started", details: "Started connection test for server: #{@server.display_name}")

      render json: {
        success: true,
        message: "Connection test started in background. You'll be notified when complete.",
        server_uuid: @server.uuid
      }
    rescue StandardError => e
      Rails.logger.error "Failed to start connection test: #{e.message}"
      render json: {
        success: false,
        message: "Failed to start connection test: #{e.message}"
      }
    end
  end

  def update_server
    begin
      # Start the server update in the background
      UpdateServerJob.perform_later(@server.id, current_user.id)

      log_activity("server_update_started", details: "Started server update for: #{@server.display_name}")

      render json: {
        success: true,
        message: "Server update started in background. This may take several minutes. You'll be notified when complete.",
        server_uuid: @server.uuid
      }
    rescue StandardError => e
      Rails.logger.error "Failed to start server update: #{e.message}"
      render json: {
        success: false,
        message: "Failed to start server update: #{e.message}"
      }
    end
  end

  def install_dokku
    begin
      # Start the Dokku installation in the background
      InstallDokkuJob.perform_later(@server.id, current_user.id)

      log_activity("dokku_installation_started", details: "Started Dokku installation for: #{@server.display_name}")

      render json: {
        success: true,
        message: "Dokku installation started in background. This may take 5-10 minutes. You'll be notified when complete.",
        server_uuid: @server.uuid
      }
    rescue StandardError => e
      Rails.logger.error "Failed to start Dokku installation: #{e.message}"
      render json: {
        success: false,
        message: "Failed to start Dokku installation: #{e.message}"
      }
    end
  end

  def restart_server
    begin
      service = SshConnectionService.new(@server)
      result = service.restart_server

      if result[:success]
        log_activity("server_restarted", details: "Successfully initiated restart on server: #{@server.display_name}")
        render json: {
          success: true,
          message: "Server restart initiated successfully! The server will be unavailable for a few minutes.",
          output: result[:output]
        }
      else
        log_activity("server_restart_failed", details: "Failed to restart server: #{@server.display_name} - #{result[:error]}")
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
    search_terms = [ @server.name, @server.display_name ] + deployment_names
    search_conditions = search_terms.map { |term| "details ILIKE ?" }
    search_values = search_terms.map { |term| "%#{term}%" }

    @activity_logs = ActivityLog.includes(:user)
                               .where(search_conditions.join(" OR "), *search_values)
                               .order(occurred_at: :desc)

    @pagy, @activity_logs = pagy(@activity_logs, limit: 20)

    log_activity("server_logs_viewed", details: "Viewed activity logs for server: #{@server.display_name}")
  end

  def firewall_rules
    @firewall_rules = @server.firewall_rules.ordered
    @common_rules = FirewallRule::COMMON_RULES

    # Check UFW status and sync if needed
    check_and_sync_ufw_status if @firewall_rules.empty?

    # Reload after potential sync
    @firewall_rules = @server.firewall_rules.ordered

    log_activity("firewall_rules_viewed", details: "Viewed firewall rules for server: #{@server.display_name}")
  end

  def sync_firewall_rules
    begin
      service = SshConnectionService.new(@server)

      # Check UFW status first
      status_result = service.check_ufw_status
      if status_result[:success]
        @server.update!(
          ufw_enabled: status_result[:enabled],
          ufw_status: status_result[:status]
        )
      end

      # List and sync rules
      result = service.list_ufw_rules

      if result[:success]
        sync_rules_to_database(result[:rules])

        respond_to do |format|
          format.json do
            render json: {
              success: true,
              message: "Firewall rules synced successfully",
              ufw_enabled: @server.ufw_enabled
            }
          end
          format.html do
            toast_success("Firewall rules synced successfully", title: "Sync Complete")
            redirect_to firewall_rules_server_path(@server)
          end
        end
      else
        respond_to do |format|
          format.json do
            render json: { success: false, message: result[:error] }, status: :unprocessable_entity
          end
          format.html do
            toast_error(result[:error], title: "Sync Failed")
            redirect_to firewall_rules_server_path(@server)
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to sync firewall rules: #{e.message}"

      respond_to do |format|
        format.json do
          render json: { success: false, message: e.message }, status: :internal_server_error
        end
        format.html do
          toast_error(e.message, title: "Sync Error")
          redirect_to firewall_rules_server_path(@server)
        end
      end
    end
  end

  def enable_ufw
    begin
      service = SshConnectionService.new(@server)
      result = service.enable_ufw

      if result[:success]
        @server.update!(ufw_enabled: true)

        log_activity("ufw_enabled", details: "Enabled UFW with Docker compatibility on server: #{@server.display_name}")

        # Build success message with warnings if any
        message = "UFW enabled successfully with Docker compatibility. Essential rules (SSH, HTTP, HTTPS) have been added."
        if result[:warnings].present?
          message += " Warnings: #{result[:warnings].join(', ')}"
        end

        respond_to do |format|
          format.json { render json: { success: true, message: message, warnings: result[:warnings] } }
          format.html do
            toast_success(message, title: "Firewall Enabled")
            redirect_to firewall_rules_server_path(@server)
          end
        end
      else
        respond_to do |format|
          format.json { render json: { success: false, message: result[:error] }, status: :unprocessable_entity }
          format.html do
            toast_error(result[:error], title: "Enable Failed")
            redirect_to firewall_rules_server_path(@server)
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to enable UFW: #{e.message}"

      respond_to do |format|
        format.json { render json: { success: false, message: e.message }, status: :internal_server_error }
        format.html do
          toast_error(e.message, title: "Enable Error")
          redirect_to firewall_rules_server_path(@server)
        end
      end
    end
  end

  def disable_ufw
    begin
      service = SshConnectionService.new(@server)
      result = service.disable_ufw

      if result[:success]
        @server.update!(ufw_enabled: false)

        log_activity("ufw_disabled", details: "Disabled UFW on server: #{@server.display_name}")

        respond_to do |format|
          format.json { render json: { success: true, message: "UFW disabled successfully" } }
          format.html do
            toast_success("UFW disabled successfully", title: "Firewall Disabled")
            redirect_to firewall_rules_server_path(@server)
          end
        end
      else
        respond_to do |format|
          format.json { render json: { success: false, message: result[:error] }, status: :unprocessable_entity }
          format.html do
            toast_error(result[:error], title: "Disable Failed")
            redirect_to firewall_rules_server_path(@server)
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to disable UFW: #{e.message}"

      respond_to do |format|
        format.json { render json: { success: false, message: e.message }, status: :internal_server_error }
        format.html do
          toast_error(e.message, title: "Disable Error")
          redirect_to firewall_rules_server_path(@server)
        end
      end
    end
  end

  def add_firewall_rule
    begin
      rule = @server.firewall_rules.build(firewall_rule_params)

      if rule.valid?
        # Add to UFW first
        service = SshConnectionService.new(@server)
        result = service.add_ufw_rule(rule.to_ufw_command)

        if result[:success]
          # Save to database
          rule.save!

          log_activity("firewall_rule_added",
                      details: "Added firewall rule #{rule.display_name} to server: #{@server.display_name}")

          respond_to do |format|
            format.json do
              render json: {
                success: true,
                message: "Firewall rule added successfully",
                rule: { id: rule.id, display_name: rule.display_name }
              }
            end
            format.html do
              toast_success("Firewall rule added successfully", title: "Rule Added")
              redirect_to firewall_rules_server_path(@server)
            end
          end
        else
          respond_to do |format|
            format.json { render json: { success: false, message: result[:error] }, status: :unprocessable_entity }
            format.html do
              toast_error(result[:error], title: "Add Failed")
              redirect_to firewall_rules_server_path(@server)
            end
          end
        end
      else
        respond_to do |format|
          format.json { render json: { success: false, message: rule.errors.full_messages.join(", ") }, status: :unprocessable_entity }
          format.html do
            toast_error(rule.errors.full_messages.join(", "), title: "Validation Failed")
            redirect_to firewall_rules_server_path(@server)
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to add firewall rule: #{e.message}"

      respond_to do |format|
        format.json { render json: { success: false, message: e.message }, status: :internal_server_error }
        format.html do
          toast_error(e.message, title: "Add Error")
          redirect_to firewall_rules_server_path(@server)
        end
      end
    end
  end

  def remove_firewall_rule
    begin
      rule = @server.firewall_rules.find(params[:rule_id])

      # Get the rule number from UFW
      service = SshConnectionService.new(@server)
      list_result = service.list_ufw_rules

      if list_result[:success]
        # Find the matching rule number
        ufw_rule = list_result[:rules].find do |r|
          r[:port_proto].include?(rule.port.to_s) &&
          r[:action] == rule.action &&
          r[:direction] == rule.direction
        end

        if ufw_rule
          # Delete from UFW
          delete_result = service.delete_ufw_rule(ufw_rule[:number])

          if delete_result[:success]
            # Delete from database
            rule.destroy!

            log_activity("firewall_rule_removed",
                        details: "Removed firewall rule #{rule.display_name} from server: #{@server.display_name}")

            respond_to do |format|
              format.json { render json: { success: true, message: "Firewall rule removed successfully" } }
              format.html do
                toast_success("Firewall rule removed successfully", title: "Rule Removed")
                redirect_to firewall_rules_server_path(@server)
              end
            end
          else
            respond_to do |format|
              format.json { render json: { success: false, message: delete_result[:error] }, status: :unprocessable_entity }
              format.html do
                toast_error(delete_result[:error], title: "Remove Failed")
                redirect_to firewall_rules_server_path(@server)
              end
            end
          end
        else
          # Rule not found in UFW, just delete from database
          rule.destroy!

          respond_to do |format|
            format.json { render json: { success: true, message: "Rule removed from database (not found in UFW)" } }
            format.html do
              toast_warning("Rule removed from database but not found in UFW", title: "Partial Remove")
              redirect_to firewall_rules_server_path(@server)
            end
          end
        end
      else
        respond_to do |format|
          format.json { render json: { success: false, message: list_result[:error] }, status: :unprocessable_entity }
          format.html do
            toast_error(list_result[:error], title: "Remove Failed")
            redirect_to firewall_rules_server_path(@server)
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to remove firewall rule: #{e.message}"

      respond_to do |format|
        format.json { render json: { success: false, message: e.message }, status: :internal_server_error }
        format.html do
          toast_error(e.message, title: "Remove Error")
          redirect_to firewall_rules_server_path(@server)
        end
      end
    end
  end

  def toggle_firewall_rule
    begin
      rule = @server.firewall_rules.find(params[:rule_id])
      rule.update!(enabled: !rule.enabled)

      log_activity("firewall_rule_toggled",
                  details: "Toggled firewall rule #{rule.display_name} to #{rule.enabled? ? 'enabled' : 'disabled'} on server: #{@server.display_name}")

      respond_to do |format|
        format.json { render json: { success: true, message: "Rule #{rule.enabled? ? 'enabled' : 'disabled'}", enabled: rule.enabled } }
        format.html do
          toast_success("Rule #{rule.enabled? ? 'enabled' : 'disabled'}", title: "Rule Updated")
          redirect_to firewall_rules_server_path(@server)
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to toggle firewall rule: #{e.message}"

      respond_to do |format|
        format.json { render json: { success: false, message: e.message }, status: :internal_server_error }
        format.html do
          toast_error(e.message, title: "Toggle Error")
          redirect_to firewall_rules_server_path(@server)
        end
      end
    end
  end

  def apply_firewall_rules
    begin
      service = SshConnectionService.new(@server)

      # Reset UFW first
      reset_result = service.reset_ufw
      unless reset_result[:success]
        raise StandardError, "Failed to reset UFW: #{reset_result[:error]}"
      end

      # Re-enable UFW if it was enabled
      if @server.ufw_enabled?
        enable_result = service.enable_ufw
        unless enable_result[:success]
          raise StandardError, "Failed to re-enable UFW: #{enable_result[:error]}"
        end
      end

      # Apply all enabled rules
      @server.firewall_rules.enabled.ordered.each do |rule|
        result = service.add_ufw_rule(rule.to_ufw_command)
        unless result[:success]
          Rails.logger.error "Failed to apply rule #{rule.display_name}: #{result[:error]}"
        end
      end

      log_activity("firewall_rules_applied",
                  details: "Applied all firewall rules to server: #{@server.display_name}")

      respond_to do |format|
        format.json { render json: { success: true, message: "All firewall rules applied successfully" } }
        format.html do
          toast_success("All firewall rules applied successfully", title: "Rules Applied")
          redirect_to firewall_rules_server_path(@server)
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to apply firewall rules: #{e.message}"

      respond_to do |format|
        format.json { render json: { success: false, message: e.message }, status: :internal_server_error }
        format.html do
          toast_error(e.message, title: "Apply Error")
          redirect_to firewall_rules_server_path(@server)
        end
      end
    end
  end

  def vulnerability_scanner
    @go_version_target = AppSetting.go_lang_version
    @scan_config = @server.vulnerability_scan_config || @server.build_vulnerability_scan_config
  end

  def check_scanner_status
    begin
      service = SshConnectionService.new(@server)

      # Check Go installation
      go_result = service.check_go_version

      # Check OSV Scanner installation
      osv_result = service.check_osv_scanner_version

      render json: {
        success: true,
        go: {
          installed: go_result[:installed],
          version: go_result[:version],
          target_version: AppSetting.go_lang_version
        },
        osv_scanner: {
          installed: osv_result[:installed],
          version: osv_result[:version]
        }
      }
    rescue StandardError => e
      Rails.logger.error "Failed to check scanner status: #{e.message}"
      render json: { success: false, message: e.message }, status: :internal_server_error
    end
  end

  def install_go
    begin
      version = AppSetting.go_lang_version

      # Start background job for Go installation
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          service = SshConnectionService.new(@server)
          result = service.install_go(version, @server.uuid)

          if result[:success]
            log_activity("go_installed", details: "Installed Go #{version} on server: #{@server.display_name}")
          end
        end
      end

      render json: { success: true, message: "Go installation started" }
    rescue StandardError => e
      Rails.logger.error "Failed to start Go installation: #{e.message}"
      render json: { success: false, message: e.message }, status: :internal_server_error
    end
  end

  def install_osv_scanner
    begin
      # Start background job for OSV Scanner installation
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          service = SshConnectionService.new(@server)
          result = service.install_osv_scanner(@server.uuid)

          if result[:success]
            log_activity("osv_scanner_installed", details: "Installed OSV Scanner on server: #{@server.display_name}")
          end
        end
      end

      render json: { success: true, message: "OSV Scanner installation started" }
    rescue StandardError => e
      Rails.logger.error "Failed to start OSV Scanner installation: #{e.message}"
      render json: { success: false, message: e.message }, status: :internal_server_error
    end
  end

  def update_scan_config
    begin
      scan_schedule = params[:scan_schedule]
      enabled = params[:enabled] == "true" || params[:enabled] == true

      unless VulnerabilityScanConfig::SCAN_SCHEDULES.key?(scan_schedule)
        respond_to do |format|
          format.json { render json: { success: false, message: "Invalid scan schedule" }, status: :unprocessable_entity }
          format.html do
            toast_error("Invalid scan schedule selected", title: "Invalid Schedule")
            redirect_to vulnerability_scanner_server_path(@server)
          end
        end
        return
      end

      config = @server.vulnerability_scan_config || @server.build_vulnerability_scan_config
      config.scan_schedule = scan_schedule
      config.enabled = enabled

      # Schedule next scan if enabled and not manual
      config.schedule_next_scan if enabled && scan_schedule != "manual"

      if config.save
        log_activity("scan_config_updated",
                    details: "Updated vulnerability scan config for server: #{@server.display_name} - Schedule: #{scan_schedule}, Enabled: #{enabled}")

        respond_to do |format|
          format.json do
            render json: {
              success: true,
              message: "Scan configuration updated successfully",
              config: {
                scan_schedule: config.scan_schedule,
                enabled: config.enabled,
                next_scan_at: config.next_scan_at&.iso8601
              }
            }
          end
          format.html do
            toast_success("Scan configuration updated successfully", title: "Configuration Updated")
            redirect_to vulnerability_scanner_server_path(@server)
          end
        end
      else
        respond_to do |format|
          format.json { render json: { success: false, message: config.errors.full_messages.join(", ") }, status: :unprocessable_entity }
          format.html do
            toast_error(config.errors.full_messages.join(", "), title: "Update Failed")
            redirect_to vulnerability_scanner_server_path(@server)
          end
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to update scan configuration: #{e.message}"

      respond_to do |format|
        format.json { render json: { success: false, message: e.message }, status: :internal_server_error }
        format.html do
          toast_error(e.message, title: "Update Error")
          redirect_to vulnerability_scanner_server_path(@server)
        end
      end
    end
  end

  def scan_all_deployments
    begin
      # Check if OSV Scanner is installed
      service = SshConnectionService.new(@server)
      osv_result = service.check_osv_scanner_version

      unless osv_result[:installed]
        respond_to do |format|
          format.json { render json: { success: false, message: "OSV Scanner is not installed on this server" }, status: :unprocessable_entity }
          format.html do
            toast_error("OSV Scanner must be installed before scanning", title: "Scanner Not Installed")
            redirect_to vulnerability_scanner_server_path(@server)
          end
        end
        return
      end

      deployments = @server.deployments
      if deployments.empty?
        respond_to do |format|
          format.json { render json: { success: false, message: "No deployments found on this server" }, status: :unprocessable_entity }
          format.html do
            toast_warning("No deployments found to scan", title: "No Deployments")
            redirect_to vulnerability_scanner_server_path(@server)
          end
        end
        return
      end

      # Start scanning all deployments in background
      scans_started = 0
      deployments.each do |deployment|
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            result = service.perform_vulnerability_scan(deployment, "manual")
            scans_started += 1 if result[:success]
          end
        end
      end

      log_activity("scan_all_deployments_started",
                  details: "Started vulnerability scans for all deployments on server: #{@server.display_name}")

      # Update last scan time
      if config = @server.vulnerability_scan_config
        config.update_last_scan
      end

      respond_to do |format|
        format.json do
          render json: {
            success: true,
            message: "Started scanning #{deployments.count} deployment(s). Check individual deployment scan pages for results.",
            deployment_count: deployments.count
          }
        end
        format.html do
          toast_success("Started scanning #{deployments.count} deployment(s)", title: "Scans Started")
          redirect_to vulnerability_scanner_server_path(@server)
        end
      end
    rescue StandardError => e
      Rails.logger.error "Failed to start scanning all deployments: #{e.message}"

      respond_to do |format|
        format.json { render json: { success: false, message: e.message }, status: :internal_server_error }
        format.html do
          toast_error(e.message, title: "Scan Error")
          redirect_to vulnerability_scanner_server_path(@server)
        end
      end
    end
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

  def check_server_status_safely
    status = @server.connection_status
    message = case status
    when "connected"
                "Server is connected. Last checked: #{@server.last_connected_ago}."
    when "failed"
                "Connection failed. Last attempt: #{@server.last_connected_ago}."
    else # 'unknown'
                "Server status is unknown. Test the connection to update."
    end

    {
      online: @server.connected?,
      message: message,
      last_checked: @server.last_connected_at
    }
  end

  def check_and_sync_ufw_status
    service = SshConnectionService.new(@server)
    status_result = service.check_ufw_status

    if status_result[:success]
      @server.update!(
        ufw_enabled: status_result[:enabled],
        ufw_status: status_result[:status]
      )

      # If UFW is enabled, sync rules
      if status_result[:enabled]
        list_result = service.list_ufw_rules
        sync_rules_to_database(list_result[:rules]) if list_result[:success]
      end
    end
  rescue StandardError => e
    Rails.logger.error "Failed to check and sync UFW status: #{e.message}"
  end

  def sync_rules_to_database(ufw_rules)
    ufw_rules.each do |ufw_rule|
      # Parse port and protocol from port_proto (e.g., "22/tcp", "80", "8000:9000/tcp")
      port_match = ufw_rule[:port_proto].match(/^(\d+(?::\d+)?)(?:\/(\w+))?$/)
      next unless port_match

      port = port_match[1]
      protocol = port_match[2] || "any"

      @server.firewall_rules.find_or_create_by!(
        port: port,
        protocol: protocol,
        action: ufw_rule[:action],
        direction: ufw_rule[:direction]
      ) do |rule|
        rule.from_ip = ufw_rule[:from] unless ufw_rule[:from] == "Anywhere"
        rule.comment = ufw_rule[:comment]
        rule.enabled = true
      end
    end

    # Remove rules that no longer exist in UFW
    existing_rules = @server.firewall_rules.all
    ufw_rule_keys = ufw_rules.map do |r|
      port_match = r[:port_proto].match(/^(\d+(?::\d+)?)(?:\/(\w+))?$/)
      next unless port_match
      "#{r[:action]}:#{r[:direction]}:#{port_match[1]}:#{port_match[2] || 'any'}"
    end.compact

    existing_rules.each do |rule|
      rule_key = "#{rule.action}:#{rule.direction}:#{rule.port}:#{rule.protocol}"
      unless ufw_rule_keys.include?(rule_key)
        rule.destroy!
        Rails.logger.info "[ServersController] Removed stale firewall rule: #{rule.display_name}"
      end
    end
  end

  def firewall_rule_params
    params.require(:firewall_rule).permit(:action, :direction, :port, :protocol, :from_ip, :to_ip, :comment)
  end
end
