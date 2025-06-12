class OauthSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  
  # Class methods for easy access to settings
  def self.get(key)
    find_by(key: key)&.value
  end
  
  def self.enabled?(key)
    find_by(key: key)&.enabled || false
  end
  
  def self.set(key, value, description = nil, enabled = false)
    setting = find_or_initialize_by(key: key)
    setting.value = value
    setting.description = description if description
    setting.enabled = enabled
    setting.save!
    setting
  end
  
  # Google OAuth specific methods
  def self.google_enabled?
    enabled?('google_oauth_enabled')
  end
  
  def self.google_client_id
    get('google_client_id')
  end
  
  def self.google_client_secret
    get('google_client_secret')
  end
  
  # Initialize default settings
  def self.setup_defaults!
    [
      {
        key: 'google_oauth_enabled',
        value: 'false',
        description: 'Enable Google OAuth sign-in for users',
        enabled: false
      },
      {
        key: 'google_client_id',
        value: '',
        description: 'Google OAuth Client ID from Google Cloud Console',
        enabled: false
      },
      {
        key: 'google_client_secret',
        value: '',
        description: 'Google OAuth Client Secret from Google Cloud Console',
        enabled: false
      }
    ].each do |setting_data|
      next if exists?(key: setting_data[:key])
      create!(setting_data)
    end
  end
end
