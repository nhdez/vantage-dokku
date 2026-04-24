class Servers::FirewallController < Servers::BaseController
  def firewall_rules
    @firewall_rules = @server.firewall_rules.ordered
    @common_rules = FirewallRule::COMMON_RULES

    check_and_sync_ufw_status if @firewall_rules.empty?
    @firewall_rules = @server.firewall_rules.ordered

    log_activity("firewall_rules_viewed", details: "Viewed firewall rules for server: #{@server.display_name}")
  end

  def sync_firewall_rules
    service = SshConnectionService.new(@server)

    status_result = service.check_ufw_status
    if status_result[:success]
      @server.update!(
        ufw_enabled: status_result[:enabled],
        ufw_status: status_result[:status]
      )
    end

    result = service.list_ufw_rules

    if result[:success]
      sync_rules_to_database(result[:rules])
      respond_to do |format|
        format.json { render json: { success: true, message: "Firewall rules synced successfully", ufw_enabled: @server.ufw_enabled } }
        format.html do
          toast_success("Firewall rules synced successfully", title: "Sync Complete")
          redirect_to firewall_rules_server_path(@server)
        end
      end
    else
      respond_to do |format|
        format.json { render json: { success: false, message: result[:error] }, status: :unprocessable_entity }
        format.html do
          toast_error(result[:error], title: "Sync Failed")
          redirect_to firewall_rules_server_path(@server)
        end
      end
    end
  rescue StandardError => e
    Rails.logger.error "Failed to sync firewall rules: #{e.message}"
    respond_to do |format|
      format.json { render json: { success: false, message: e.message }, status: :internal_server_error }
      format.html do
        toast_error(e.message, title: "Sync Error")
        redirect_to firewall_rules_server_path(@server)
      end
    end
  end

  def enable_ufw
    service = SshConnectionService.new(@server)
    result = service.enable_ufw

    if result[:success]
      @server.update!(ufw_enabled: true)
      log_activity("ufw_enabled", details: "Enabled UFW with Docker compatibility on server: #{@server.display_name}")

      message = "UFW enabled successfully with Docker compatibility. Essential rules (SSH, HTTP, HTTPS) have been added."
      message += " Warnings: #{result[:warnings].join(', ')}" if result[:warnings].present?

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

  def disable_ufw
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

  def add_firewall_rule
    rule = @server.firewall_rules.build(firewall_rule_params)

    if rule.valid?
      service = SshConnectionService.new(@server)
      result = service.add_ufw_rule(rule.to_ufw_command)

      if result[:success]
        rule.save!
        log_activity("firewall_rule_added",
                    details: "Added firewall rule #{rule.display_name} to server: #{@server.display_name}")

        respond_to do |format|
          format.json { render json: { success: true, message: "Firewall rule added successfully", rule: { id: rule.id, display_name: rule.display_name } } }
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

  def remove_firewall_rule
    rule = @server.firewall_rules.find(params[:rule_id])
    service = SshConnectionService.new(@server)
    list_result = service.list_ufw_rules

    if list_result[:success]
      ufw_rule = list_result[:rules].find do |r|
        r[:port_proto].include?(rule.port.to_s) &&
        r[:action] == rule.action &&
        r[:direction] == rule.direction
      end

      if ufw_rule
        delete_result = service.delete_ufw_rule(ufw_rule[:number])

        if delete_result[:success]
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

  def toggle_firewall_rule
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

  def apply_firewall_rules
    service = SshConnectionService.new(@server)

    reset_result = service.reset_ufw
    raise StandardError, "Failed to reset UFW: #{reset_result[:error]}" unless reset_result[:success]

    if @server.ufw_enabled?
      enable_result = service.enable_ufw
      raise StandardError, "Failed to re-enable UFW: #{enable_result[:error]}" unless enable_result[:success]
    end

    @server.firewall_rules.enabled.ordered.each do |rule|
      result = service.add_ufw_rule(rule.to_ufw_command)
      Rails.logger.error "Failed to apply rule #{rule.display_name}: #{result[:error]}" unless result[:success]
    end

    log_activity("firewall_rules_applied", details: "Applied all firewall rules to server: #{@server.display_name}")

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

  private

  def check_and_sync_ufw_status
    service = SshConnectionService.new(@server)
    status_result = service.check_ufw_status

    if status_result[:success]
      @server.update!(
        ufw_enabled: status_result[:enabled],
        ufw_status: status_result[:status]
      )

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

    existing_rules = @server.firewall_rules.all
    ufw_rule_keys = ufw_rules.map do |r|
      port_match = r[:port_proto].match(/^(\d+(?::\d+)?)(?:\/(\w+))?$/)
      next unless port_match
      "#{r[:action]}:#{r[:direction]}:#{port_match[1]}:#{port_match[2] || 'any'}"
    end.compact

    existing_rules.each do |rule|
      rule_key = "#{rule.action}:#{rule.direction}:#{rule.port}:#{rule.protocol}"
      rule.destroy! unless ufw_rule_keys.include?(rule_key)
    end
  end

  def firewall_rule_params
    params.require(:firewall_rule).permit(:action, :direction, :port, :protocol, :from_ip, :to_ip, :comment)
  end
end
