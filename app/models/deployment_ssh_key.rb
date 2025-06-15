class DeploymentSshKey < ApplicationRecord
  belongs_to :deployment
  belongs_to :ssh_key
  
  validates :deployment_id, uniqueness: { scope: :ssh_key_id }
  validate :ssh_key_belongs_to_deployment_user
  
  private
  
  def ssh_key_belongs_to_deployment_user
    return unless deployment.present? && ssh_key.present?
    
    unless deployment.user == ssh_key.user
      errors.add(:ssh_key, "must belong to the same user as the deployment")
    end
  end
end
