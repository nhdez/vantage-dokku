class UpdateEnvironmentJob < ApplicationJob
  queue_as :default

  def perform(deployment_id, user_id, env_vars_params)
    @deployment = Deployment.find(deployment_id)
    @user = User.find(user_id)
    
    begin
      # Start a transaction to ensure data consistency
      ActiveRecord::Base.transaction do
        # Clear existing environment variables
        @deployment.environment_variables.destroy_all
        
        # Create new environment variables from the form
        env_vars_params.each do |index, env_var_data|
          key = env_var_data['key']&.strip&.upcase
          value = env_var_data['value']
          description = env_var_data['description']&.strip
          
          # Skip empty entries
          next if key.blank?
          
          @deployment.environment_variables.create!(
            key: key,
            value: value,
            description: description
          )
        end
        
        # Sync environment variables to Dokku server
        service = SshConnectionService.new(@deployment.server)
        env_vars = @deployment.environment_variables.pluck(:key, :value).to_h
        result = service.sync_dokku_environment_variables(@deployment.dokku_app_name, env_vars)
        
        if result[:success]
          count = @deployment.environment_variables.count
          
          ActionCable.server.broadcast("update_environment_#{@deployment.uuid}", {
            success: true,
            message: "Environment variables updated successfully! #{count} variable#{'s' unless count == 1} configured.",
            count: count,
            variables: @deployment.environment_variables.reload.map do |var|
              {
                key: var.key,
                description: var.description,
                sensitive: var.sensitive?
              }
            end
          })
        else
          # Rollback the transaction since server sync failed
          raise StandardError, "Failed to sync environment variables to server: #{result[:error]}"
        end
      end
      
    rescue ActiveRecord::RecordInvalid => e
      ActionCable.server.broadcast("update_environment_#{@deployment.uuid}", {
        success: false,
        message: "Failed to save environment variables: #{e.record.errors.full_messages.join(', ')}"
      })
      
    rescue StandardError => e
      Rails.logger.error "Environment variables update failed: #{e.message}"
      
      ActionCable.server.broadcast("update_environment_#{@deployment.uuid}", {
        success: false,
        message: "An unexpected error occurred: #{e.message}"
      })
    end
  end
end