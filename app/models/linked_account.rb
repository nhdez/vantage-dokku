class LinkedAccount < ApplicationRecord
  belongs_to :user
  
  SUPPORTED_PROVIDERS = %w[github].freeze
  
  validates :provider, presence: true, inclusion: { in: SUPPORTED_PROVIDERS }
  validates :access_token, presence: true
  validates :user_id, uniqueness: { scope: :provider, message: "already has a linked account for this provider" }
  
  scope :active, -> { where(active: true) }
  scope :for_provider, ->(provider) { where(provider: provider) }
  scope :github, -> { for_provider('github') }
  
  encrypts :access_token
  encrypts :refresh_token
  
  serialize :metadata, coder: JSON
  
  def display_name
    case provider
    when 'github'
      account_username.present? ? "@#{account_username}" : "GitHub Account"
    else
      "#{provider.capitalize} Account"
    end
  end
  
  def provider_icon
    case provider
    when 'github'
      'fab fa-github'
    else
      'fas fa-link'
    end
  end
  
  def provider_color
    case provider
    when 'github'
      'dark'
    else
      'secondary'
    end
  end
  
  def github?
    provider == 'github'
  end
  
  def token_valid?
    return false if access_token.blank?
    return true if token_expires_at.nil? # GitHub personal access tokens don't expire by default
    token_expires_at > Time.current
  end
  
  def token_expired?
    !token_valid?
  end
  
  def deactivate!
    update!(active: false)
  end
  
  def activate!
    update!(active: true)
  end
  
  def test_connection
    case provider
    when 'github'
      GitHubService.new(self).test_connection
    else
      { success: false, error: "Provider #{provider} not supported" }
    end
  end
  
  def last_connected_at
    metadata&.dig('last_connected_at')&.in_time_zone
  end
  
  def update_last_connected!
    self.metadata ||= {}
    self.metadata['last_connected_at'] = Time.current.iso8601
    save!
  end
  
  def connection_status
    return 'disconnected' unless active?
    return 'expired' if token_expired?
    
    last_connected = last_connected_at
    return 'unknown' if last_connected.nil?
    
    if last_connected > 1.hour.ago
      'connected'
    elsif last_connected > 1.day.ago
      'stale'
    else
      'outdated'
    end
  end
  
  def connection_status_color
    case connection_status
    when 'connected'
      'success'
    when 'stale'
      'warning'
    when 'expired', 'disconnected', 'outdated'
      'danger'
    else
      'secondary'
    end
  end
  
  def connection_status_icon
    case connection_status
    when 'connected'
      'fas fa-check-circle'
    when 'stale'
      'fas fa-clock'
    when 'expired'
      'fas fa-times-circle'
    when 'disconnected'
      'fas fa-unlink'
    when 'outdated'
      'fas fa-exclamation-triangle'
    else
      'fas fa-question-circle'
    end
  end
end
