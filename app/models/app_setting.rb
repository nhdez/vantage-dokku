class AppSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true
  validates :setting_type, inclusion: { in: %w[string boolean integer] }
  
  scope :by_key, ->(key) { find_by(key: key) }
  
  # Class method to get a setting value with optional default
  def self.get(key, default = nil)
    setting = find_by(key: key)
    return default unless setting
    
    case setting.setting_type
    when 'boolean'
      setting.value == 'true'
    when 'integer'
      setting.value.to_i
    else
      setting.value
    end
  end
  
  # Class method to set a setting value
  def self.set(key, value, description: nil, setting_type: 'string')
    setting = find_or_initialize_by(key: key)
    setting.value = value.to_s
    setting.description = description if description
    setting.setting_type = setting_type
    setting.save!
  end
  
  # Get the typed value
  def typed_value
    case setting_type
    when 'boolean'
      value == 'true'
    when 'integer'
      value.to_i
    else
      value
    end
  end
end
