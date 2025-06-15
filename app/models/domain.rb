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
