require 'fileutils'

class Server < ApplicationRecord
  include ActionView::Helpers::DateHelper
  
  belongs_to :user
  has_many :deployments, dependent: :destroy
  
  # Encrypt sensitive password data
  encrypts :password, deterministic: false
  
  validates :name, presence: true, length: { minimum: 1, maximum: 50 }
  validates :ip, presence: true, format: { with: /\A(?:[0-9]{1,3}\.){3}[0-9]{1,3}\z/, message: "must be a valid IP address" }
  validates :username, presence: true, length: { minimum: 1, maximum: 50 }
  validates :port, presence: true, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65535 }
  validates :uuid, presence: true, uniqueness: true
  validates :internal_ip, format: { with: /\A(?:[0-9]{1,3}\.){3}[0-9]{1,3}\z/, message: "must be a valid IP address" }, allow_blank: true
  validates :service_provider, length: { maximum: 100 }, allow_blank: true
  validates :name, uniqueness: { scope: :user_id, message: "already exists for this user" }
  validates :password, length: { minimum: 1 }, allow_blank: true
  validates :connection_status, inclusion: { in: %w[unknown connected failed] }
  
  before_validation :generate_uuid, on: :create
  
  def to_param
    uuid
  end
  
  def display_name
    "#{name} (#{ip})"
  end
  
  def connection_details
    details = {
      host: ip,
      username: username,
      port: port,
      keys: ssh_key_paths
    }
    
    # Add password for fallback authentication if SSH key fails
    details[:password] = password if password.present?
    
    details
  end
  
  def has_password_auth?
    password.present?
  end
  
  def has_key_auth?
    ssh_key_paths.any?
  end
  
  def ssh_key_paths
    paths = []
    
    # Check environment variables first (they take precedence)
    if ENV['DOKKU_SSH_KEY_PATH'].present?
      paths << ENV['DOKKU_SSH_KEY_PATH']
    else
      # Use database settings
      ssh_key_path = AppSetting.get('dokku_ssh_key_path')
      private_key = AppSetting.get('dokku_ssh_private_key')
      
      if ssh_key_path.present? && private_key.present?
        # Create temporary key file if it doesn't exist
        key_file_path = create_temp_ssh_key_file(ssh_key_path, private_key)
        paths << key_file_path if key_file_path
      end
    end
    
    paths.compact
  end
  
  def connected?
    connection_status == 'connected'
  end
  
  def connection_failed?
    connection_status == 'failed'
  end
  
  def connection_unknown?
    connection_status == 'unknown'
  end
  
  def connection_status_badge_class
    case connection_status
    when 'connected'
      'bg-success'
    when 'failed'
      'bg-danger'
    else
      'bg-warning text-dark'
    end
  end
  
  def connection_status_icon
    case connection_status
    when 'connected'
      'fas fa-check-circle'
    when 'failed'
      'fas fa-times-circle'
    else
      'fas fa-question-circle'
    end
  end
  
  def formatted_ram
    return 'Unknown' if ram_total.blank?
    ram_total
  end
  
  def formatted_disk
    return 'Unknown' if disk_total.blank?
    disk_total
  end
  
  def last_connected_ago
    return 'Never' if last_connected_at.blank?
    "#{time_ago_in_words(last_connected_at)} ago"
  end
  
  def dokku_installed?
    dokku_version.present?
  end
  
  def formatted_dokku_version
    return 'Not detected' if dokku_version.blank?
    dokku_version
  end
  
  private
  
  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
  
  def create_temp_ssh_key_file(key_path, private_key_content)
    return nil if private_key_content.blank?
    
    # Ensure the directory exists
    key_dir = File.dirname(key_path)
    FileUtils.mkdir_p(key_dir) unless File.directory?(key_dir)
    
    # Write the private key to the file
    File.write(key_path, private_key_content)
    
    # Set correct permissions (readable only by owner)
    File.chmod(0600, key_path)
    
    key_path
  rescue => e
    Rails.logger.error "Failed to create SSH key file: #{e.message}"
    nil
  end
end
