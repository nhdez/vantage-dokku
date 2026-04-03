class DeleteDomainJob < ApplicationJob
  queue_as :default

  def perform(deployment_id, domain_id, user_id)
    @deployment = Deployment.find(deployment_id)
    @domain = Domain.find(domain_id)
    @user = User.find(user_id)

    Rails.logger.info "[DeleteDomainJob] Starting domain deletion for #{@domain.name} from deployment #{@deployment.name}"

    begin
      domain_name = @domain.name

      # Remove domain from Dokku and clean up SSL certificates
      service = SshConnectionService.new(@deployment.server)
      result = service.remove_domain_from_app(@deployment.dokku_app_name, domain_name)

      if result[:success]
        # Delete the domain record from database
        @domain.destroy!

        # Log the successful deletion
        ActivityLog.create!(
          user: @user,
          action: "domain_deleted",
          details: "Deleted domain '#{domain_name}' from deployment '#{@deployment.name}'",
          occurred_at: Time.current
        )

        # If there are other domains, reconfigure SSL for them
        if @deployment.domains.any?
          Rails.logger.info "[DeleteDomainJob] Reconfiguring SSL for remaining domains"
          remaining_domains = @deployment.domains.pluck(:name)
          ssl_result = service.sync_dokku_domains(@deployment.dokku_app_name, remaining_domains)

          if ssl_result[:success]
            Rails.logger.info "[DeleteDomainJob] SSL reconfigured successfully"
          else
            Rails.logger.error "[DeleteDomainJob] Failed to reconfigure SSL: #{ssl_result[:error]}"
          end
        end

        Rails.logger.info "[DeleteDomainJob] Domain deletion completed successfully"
      else
        Rails.logger.error "[DeleteDomainJob] Failed to remove domain from server: #{result[:error]}"

        # Log the failure but still remove from database if server removal failed
        # (domain might not exist on server)
        @domain.destroy!

        ActivityLog.create!(
          user: @user,
          action: "domain_deleted",
          details: "Deleted domain '#{domain_name}' from database (server removal failed: #{result[:error]})",
          occurred_at: Time.current
        )
      end

    rescue StandardError => e
      Rails.logger.error "[DeleteDomainJob] Domain deletion failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")

      ActivityLog.create!(
        user: @user,
        action: "domain_deletion_failed",
        details: "Failed to delete domain '#{@domain.name}': #{e.message}",
        occurred_at: Time.current
      )
    end
  end
end
