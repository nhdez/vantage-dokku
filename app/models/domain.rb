class Domain < ApplicationRecord
  belongs_to :deployment
  
  validates :name, presence: true, 
                   format: { 
                     with: /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/i, 
                     message: "must be a valid domain name" 
                   },
                   length: { maximum: 255 }
  validates :name, uniqueness: { scope: :deployment_id, message: "already exists for this deployment" }
  
  validate :only_one_default_domain_per_deployment
  
  scope :ordered, -> { order(:default_domain => :desc, :created_at => :asc) }
  scope :default_first, -> { order(:default_domain => :desc, :created_at => :asc) }
  
  before_save :normalize_domain_name
  before_create :set_as_default_if_first_domain
  
  def display_name
    name
  end
  
  def full_url(protocol: 'https')
    return nil unless name.present?
    ssl_enabled? && protocol == 'https' ? "https://#{name}" : "http://#{name}"
  end
  
  def ssl_status_text
    if ssl_enabled?
      "SSL Enabled"
    elsif ssl_error_message.present?
      "SSL Failed"
    else
      "SSL Disabled"
    end
  end
  
  def ssl_status_class
    if ssl_enabled?
      'bg-success'
    elsif ssl_error_message.present?
      'bg-danger'
    else
      'bg-secondary'
    end
  end
  
  def domain_status_text
    if ssl_enabled?
      "Active (SSL)"
    elsif ssl_error_message.present?
      "Error"
    else
      "Active (No SSL)"
    end
  end
  
  def domain_status_class
    if ssl_enabled?
      'bg-success'
    elsif ssl_error_message.present?
      'bg-danger'
    else
      'bg-warning text-dark'
    end
  end
  
  # Real-time SSL verification methods
  def verify_ssl_status
    @ssl_verification_result ||= begin
      SslVerificationService.verify_domain_ssl(self)
    rescue StandardError => e
      Rails.logger.error "SSL verification failed for domain #{name}: #{e.message}"
      {
        domain: name,
        ssl_active: false,
        ssl_valid: false,
        https_accessible: false,
        http_accessible: false,
        ssl_certificate_info: nil,
        error_message: "Verification error: #{e.message}",
        response_time: nil,
        checked_at: Time.current
      }
    end
  end
  
  def ssl_actually_working?
    verify_ssl_status[:ssl_active] && verify_ssl_status[:https_accessible]
  end
  
  def ssl_certificate_valid?
    verify_ssl_status[:ssl_valid]
  end
  
  def real_ssl_status_text
    result = verify_ssl_status
    
    if result[:https_accessible] && result[:ssl_valid]
      "SSL Active"
    elsif result[:ssl_active] && !result[:ssl_valid]
      "SSL Invalid"
    elsif result[:http_accessible] && !result[:https_accessible]
      "SSL Not Configured"
    elsif !result[:http_accessible]
      "Domain Not Accessible"
    else
      "SSL Pending"
    end
  end
  
  def real_ssl_status_color
    result = verify_ssl_status
    
    if result[:https_accessible] && result[:ssl_valid]
      'success'
    elsif result[:ssl_active] && !result[:ssl_valid]
      'danger'
    elsif result[:http_accessible] && !result[:https_accessible]
      'warning'
    elsif !result[:http_accessible]
      'danger'
    else
      'secondary'
    end
  end
  
  def real_ssl_status_icon
    result = verify_ssl_status
    
    if result[:https_accessible] && result[:ssl_valid]
      'fas fa-lock'
    elsif result[:ssl_active] && !result[:ssl_valid]
      'fas fa-exclamation-triangle'
    elsif result[:http_accessible] && !result[:https_accessible]
      'fas fa-clock'
    elsif !result[:http_accessible]
      'fas fa-times-circle'
    else
      'fas fa-question-circle'
    end
  end
  
  def ssl_certificate_info
    verify_ssl_status[:ssl_certificate_info]
  end
  
  def ssl_verification_error
    verify_ssl_status[:error_message]
  end
  
  def ssl_response_time
    verify_ssl_status[:response_time]
  end
  
  def last_ssl_check_time
    verify_ssl_status[:checked_at]
  end
  
  # Clear cached SSL verification (useful for forcing fresh checks)
  def clear_ssl_verification_cache
    @ssl_verification_result = nil
  end
  
  private
  
  def normalize_domain_name
    return unless name.present?
    self.name = name.downcase.strip
  end
  
  def set_as_default_if_first_domain
    # If this is the first domain for the deployment, make it the default
    if deployment.domains.count == 0
      self.default_domain = true
    end
  end
  
  def only_one_default_domain_per_deployment
    return unless default_domain?
    
    existing_default = deployment.domains.where(default_domain: true)
    existing_default = existing_default.where.not(id: id) if persisted?
    
    if existing_default.exists?
      errors.add(:default_domain, "can only have one default domain per deployment")
    end
  end
end
