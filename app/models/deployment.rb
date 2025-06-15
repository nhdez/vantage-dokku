class Deployment < ApplicationRecord
  belongs_to :server
  belongs_to :user
  
  has_many :deployment_ssh_keys, dependent: :destroy
  has_many :ssh_keys, through: :deployment_ssh_keys
  has_many :environment_variables, dependent: :destroy
  has_many :domains, dependent: :destroy
  has_one :database_configuration, dependent: :destroy
  has_many :application_healths, dependent: :destroy
  
  validates :name, presence: true, length: { maximum: 100 }
  validates :name, uniqueness: { scope: :user_id, message: "has already been used for another deployment" }
  validates :dokku_app_name, presence: true, uniqueness: true
  validates :dokku_app_name, format: { 
    with: /\A[a-z0-9-]+\z/, 
    message: "must contain only lowercase letters, numbers, and hyphens"
  }
  validates :description, length: { maximum: 1000 }, allow_blank: true
  validates :uuid, presence: true, uniqueness: true
  
  validate :server_must_have_dokku_installed
  
  before_validation :generate_uuid, on: :create
  before_validation :generate_dokku_app_name, on: :create
  before_validation :normalize_dokku_app_name
  
  after_create :create_dokku_app_async
  
  scope :for_server, ->(server) { where(server: server) }
  scope :recent, -> { order(created_at: :desc) }
  
  # Word lists for generating random app names
  ADJECTIVES = %w[
    ancient brave calm clever bold bright cosmic deep elegant fierce gentle
    golden happy infinite jolly kind light mighty noble peaceful quiet
    radiant serene swift wise wonderful brave clever noble peaceful wise
    arctic autumn blazing crystal dancing electric frozen glowing misty
    mystic ocean silver storm sunset thunder winter cosmic stellar lunar
    royal emerald crimson azure violet amber bronze copper iron steel
  ].freeze
  
  NOUNS = %w[
    butterfly kingdom mountain river forest ocean star moon dream whisper
    thunder lightning rainbow phoenix dragon eagle wolf bear lion tiger
    elephant dolphin whale shark turtle dove hawk falcon swan eagle
    crystal diamond ruby emerald sapphire pearl jade amber opal garnet
    castle fortress tower bridge valley meadow garden waterfall lagoon
    island continent plateau canyon desert oasis glacier volcano mountain
    wisdom courage honor justice truth beauty grace strength harmony peace
  ].freeze
  
  def to_param
    uuid
  end
  
  def display_name
    name
  end
  
  def server_name
    server&.name || 'Unknown Server'
  end
  
  def dokku_url
    # Use default domain if available, otherwise fallback to nip.io
    default_domain = domains.find_by(default_domain: true)
    if default_domain
      default_domain.full_url
    elsif server&.ip.present? && dokku_app_name.present?
      "http://#{dokku_app_name}.#{server.ip}.nip.io"
    else
      nil
    end
  end
  
  def default_domain
    domains.find_by(default_domain: true)
  end
  
  def has_custom_domains?
    domains.any?
  end
  
  def has_database_configured?
    database_configuration.present?
  end
  
  def database_type
    database_configuration&.database_type
  end
  
  def can_deploy?
    server&.dokku_installed? && server&.connection_status == 'connected'
  end
  
  def deployment_status
    # This will be expanded later when we add actual deployment functionality
    'not_deployed'
  end
  
  def status_badge_class
    case deployment_status
    when 'deployed'
      'bg-success'
    when 'deploying'
      'bg-warning text-dark'
    when 'failed'
      'bg-danger'
    else
      'bg-secondary'
    end
  end
  
  def status_text
    case deployment_status
    when 'deployed'
      'Deployed'
    when 'deploying'
      'Deploying'
    when 'failed'
      'Failed'
    else
      'Not Deployed'
    end
  end
  
  def status_icon
    case deployment_status
    when 'deployed'
      'fas fa-check-circle'
    when 'deploying'
      'fas fa-spinner fa-spin'
    when 'failed'
      'fas fa-times-circle'
    else
      'fas fa-clock'
    end
  end
  
  def latest_health_check
    application_healths.recent.first
  end
  
  def last_20_health_checks
    application_healths.last_20
  end
  
  def current_health_status
    latest_health_check&.status || 'unknown'
  end
  
  def health_status_color
    latest_health_check&.status_color || 'secondary'
  end
  
  def health_status_icon
    latest_health_check&.status_icon || 'fas fa-question-circle'
  end
  
  def is_healthy?
    latest_health_check&.healthy? || false
  end
  
  def is_unhealthy?
    latest_health_check&.unhealthy? || false
  end
  
  def health_uptime_percentage
    checks = last_20_health_checks
    return 0 if checks.empty?
    
    healthy_count = checks.count(&:healthy?)
    ((healthy_count.to_f / checks.count) * 100).round(1)
  end
  
  def last_downtime
    application_healths.unhealthy.recent.first&.checked_at
  end
  
  def needs_health_notification?
    # Send notification if app has been down for more than 1 check
    recent_checks = application_healths.recent.limit(2)
    recent_checks.count >= 2 && recent_checks.all?(&:unhealthy?)
  end
  
  private
  
  def generate_uuid
    return if uuid.present?
    self.uuid = SecureRandom.uuid
  end
  
  def generate_dokku_app_name
    return if dokku_app_name.present?
    
    # Generate a random combination like "brave-butterfly-kingdom"
    max_attempts = 10
    attempts = 0
    
    begin
      attempts += 1
      adjective = ADJECTIVES.sample
      noun1 = NOUNS.sample
      noun2 = NOUNS.sample
      
      # Ensure we don't repeat words
      noun2 = NOUNS.sample while noun1 == noun2
      
      generated_name = "#{adjective}-#{noun1}-#{noun2}"
      
      # Check if this name already exists
      unless Deployment.exists?(dokku_app_name: generated_name)
        self.dokku_app_name = generated_name
        break
      end
      
    end while attempts < max_attempts
    
    # Fallback to timestamp-based name if we couldn't generate a unique one
    if dokku_app_name.blank?
      timestamp = Time.current.to_i
      self.dokku_app_name = "app-#{timestamp}"
    end
  end
  
  def normalize_dokku_app_name
    return unless dokku_app_name.present?
    
    # Ensure dokku app name follows Dokku naming conventions
    self.dokku_app_name = dokku_app_name
                            .downcase
                            .gsub(/[^a-z0-9-]/, '-')    # Replace invalid characters with dashes
                            .gsub(/-+/, '-')            # Collapse multiple dashes
                            .gsub(/^-|-$/, '')          # Remove leading and trailing dashes
  end
  
  def server_must_have_dokku_installed
    return unless server.present?
    
    unless server.dokku_installed?
      errors.add(:server, "must have Dokku installed to create deployments")
    end
  end
  
  def create_dokku_app_async
    # Create the Dokku app automatically when deployment is created
    # In development, run synchronously for immediate feedback
    # In production, run in background to avoid blocking the user interface
    if Rails.env.development?
      CreateDokkuAppJob.perform_now(self)
    else
      CreateDokkuAppJob.perform_later(self)
    end
  rescue StandardError => e
    Rails.logger.error "Failed to execute Dokku app creation job: #{e.message}"
    # Don't fail the deployment creation if job execution fails
  end
end
