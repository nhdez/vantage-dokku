class MarkExistingManagedDatabaseUrls < ActiveRecord::Migration[8.0]
  def up
    # Find all deployments with configured databases
    DatabaseConfiguration.where(configured: true).find_each do |db_config|
      deployment = db_config.deployment
      env_var_name = db_config.environment_variable_name
      
      # Mark the DATABASE_URL as system-managed
      env_var = deployment.environment_variables.find_by(key: env_var_name)
      if env_var
        env_var.update_column(:source, 'system')
        puts "Marked #{env_var_name} as system-managed for deployment #{deployment.uuid}"
      end
      
      # Mark REDIS_URL if Redis is enabled
      if db_config.redis_enabled?
        redis_env_var_name = db_config.redis_environment_variable_name
        redis_env_var = deployment.environment_variables.find_by(key: redis_env_var_name)
        if redis_env_var
          redis_env_var.update_column(:source, 'system')
          puts "Marked #{redis_env_var_name} as system-managed for deployment #{deployment.uuid}"
        end
      end
    end
  end
  
  def down
    # Revert all system-managed back to user-managed
    EnvironmentVariable.where(source: 'system').update_all(source: 'user')
  end
end
