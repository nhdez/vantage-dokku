class UpdateDomainsJob < ApplicationJob
  queue_as :default

  def perform(deployment_id, user_id, domains_hash)
    @deployment = Deployment.find(deployment_id)
    @user = User.find(user_id)
    
    begin
      Rails.logger.info "Starting domain update for deployment: #{@deployment.display_name}"
      
      # Start a transaction to ensure data consistency
      ActiveRecord::Base.transaction do
        # Clear existing domains
        @deployment.domains.destroy_all
        
        # Create new domains from the form
        domains_hash.each do |index, domain_data|
          domain_name = domain_data["name"]&.strip&.downcase
          is_default = domain_data["default_domain"] == "1"
          
          # Skip empty entries
          next if domain_name.blank?
          
          @deployment.domains.create!(
            name: domain_name,
            default_domain: is_default
          )
        end
        
        # If no domain was marked as default, make the first one default
        if @deployment.domains.any? && !@deployment.domains.exists?(default_domain: true)
          @deployment.domains.first.update!(default_domain: true)
        end
        
        # Sync domains to Dokku server and configure SSL
        service = SshConnectionService.new(@deployment.server)
        domain_names = @deployment.domains.pluck(:name)
        result = service.sync_dokku_domains(@deployment.dokku_app_name, domain_names)
        
        if result[:success]
          count = @deployment.domains.count
          
          Rails.logger.info "Domains updated successfully for deployment: #{@deployment.display_name} - #{count} domains"
          
          # Broadcast success to ActionCable
          ActionCable.server.broadcast("update_domains_#{@deployment.uuid}", {
            success: true,
            message: "Domains updated successfully! #{count} domain#{'s' unless count == 1} configured and SSL enabled.",
            count: count,
            domains: @deployment.domains.map { |d| { name: d.name, default: d.default_domain } }
          })
        else
          Rails.logger.error "Failed to sync domains for deployment: #{@deployment.display_name} - #{result[:error]}"
          
          # Rollback the transaction since server sync failed
          raise ActiveRecord::Rollback, "Domain sync failed: #{result[:error]}"
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Domain validation failed: #{e.record.errors.full_messages.join(', ')}"
      
      # Broadcast error to ActionCable
      ActionCable.server.broadcast("update_domains_#{@deployment.uuid}", {
        success: false,
        message: "Failed to save domains: #{e.record.errors.full_messages.join(', ')}"
      })
    rescue StandardError => e
      Rails.logger.error "Domain update failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      # Broadcast error to ActionCable
      ActionCable.server.broadcast("update_domains_#{@deployment.uuid}", {
        success: false,
        message: "An unexpected error occurred: #{e.message}"
      })
    end
  end
end