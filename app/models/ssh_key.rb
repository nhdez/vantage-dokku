class SshKey < ApplicationRecord
  belongs_to :user
  
  has_many :deployment_ssh_keys, dependent: :destroy
  has_many :deployments, through: :deployment_ssh_keys
  
  validates :name, presence: true, length: { maximum: 100 }
  validates :name, uniqueness: { scope: :user_id, message: "has already been used for another SSH key" }
  validates :public_key, presence: true, length: { maximum: 8192 }
  validates :public_key, format: { 
    with: /\A(ssh-rsa|ssh-dss|ssh-ed25519|ecdsa-sha2-nistp256|ecdsa-sha2-nistp384|ecdsa-sha2-nistp521)\s+[A-Za-z0-9+\/]+=*(\s+.*)?$/, 
    message: "must be a valid SSH public key",
    multiline: true
  }
  
  scope :active, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :expired, -> { where('expires_at IS NOT NULL AND expires_at <= ?', Time.current) }
  
  def expired?
    expires_at.present? && expires_at <= Time.current
  end
  
  def active?
    !expired?
  end
  
  def fingerprint
    return nil unless public_key.present?
    
    # Extract the key part (without ssh-rsa prefix and comment)
    key_parts = public_key.strip.split(' ')
    return nil if key_parts.length < 2
    
    key_data = key_parts[1]
    
    begin
      # Decode base64 and create MD5 fingerprint
      decoded = Base64.decode64(key_data)
      digest = Digest::MD5.hexdigest(decoded)
      # Format as xx:xx:xx:xx...
      digest.scan(/../).join(':')
    rescue StandardError
      nil
    end
  end
  
  def key_type
    return nil unless public_key.present?
    public_key.strip.split(' ').first
  end
  
  def comment
    return nil unless public_key.present?
    parts = public_key.strip.split(' ', 3)
    parts.length >= 3 ? parts[2] : nil
  end
  
  def display_name
    name
  end
  
  def expires_in_days
    return nil unless expires_at.present?
    return 0 if expired?
    
    days = ((expires_at - Time.current) / 1.day).ceil
    [days, 0].max
  end
  
  def status_badge_class
    if expired?
      'bg-danger'
    elsif expires_at.present? && expires_in_days <= 7
      'bg-warning text-dark'
    else
      'bg-success'
    end
  end
  
  def status_text
    if expired?
      'Expired'
    elsif expires_at.present?
      if expires_in_days <= 7
        "Expires in #{expires_in_days} day#{'s' unless expires_in_days == 1}"
      else
        "Expires #{expires_at.strftime('%B %d, %Y')}"
      end
    else
      'Active'
    end
  end
end
