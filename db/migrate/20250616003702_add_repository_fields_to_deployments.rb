class AddRepositoryFieldsToDeployments < ActiveRecord::Migration[8.0]
  def change
    add_column :deployments, :repository_url, :text
    add_column :deployments, :deployment_method, :string, default: 'manual'
    add_column :deployments, :deployment_status, :string, default: 'pending'
    add_column :deployments, :deployment_logs, :text
    add_column :deployments, :repository_branch, :string, default: 'main'
    add_column :deployments, :last_deployment_at, :datetime
    
    add_index :deployments, :deployment_status
    add_index :deployments, :deployment_method
  end
end
