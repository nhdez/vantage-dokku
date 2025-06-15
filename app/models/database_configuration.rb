class DatabaseConfiguration < ApplicationRecord
  belongs_to :deployment
  
  validates :database_type, presence: true, inclusion: { in: %w[postgres mysql mariadb mongo], message: "must be a supported database type" }
  validates :database_name, presence: true, uniqueness: true, 
                             format: { 
                               with: /\A[a-z][a-z0-9-]*[a-z0-9]\z/, 
                               message: "must be lowercase letters, numbers, and hyphens only" 
                             },
                             length: { maximum: 100 }
  
  validate :check_environment_variable_conflict
  
  before_validation :generate_database_name, on: :create
  before_validation :generate_credentials, on: :create
  before_validation :generate_redis_name, on: :create, if: :redis_enabled?
  
  # Database type constants
  SUPPORTED_DATABASES = {
    'postgres' => {
      name: 'PostgreSQL',
      plugin_url: 'https://github.com/dokku/dokku-postgres.git',
      env_var: 'DATABASE_URL'
    },
    'mysql' => {
      name: 'MySQL',
      plugin_url: 'https://github.com/dokku/dokku-mysql.git',
      env_var: 'DATABASE_URL'
    },
    'mariadb' => {
      name: 'MariaDB',
      plugin_url: 'https://github.com/dokku/dokku-mariadb.git',
      env_var: 'DATABASE_URL'
    },
    'mongo' => {
      name: 'MongoDB',
      plugin_url: 'https://github.com/dokku/dokku-mongo.git',
      env_var: 'MONGO_URL'
    }
  }.freeze
  
  REDIS_CONFIG = {
    name: 'Redis',
    plugin_url: 'https://github.com/dokku/dokku-redis.git',
    env_var: 'REDIS_URL'
  }.freeze
  
  # Word lists for generating random database names
  ADJECTIVES = %w[
    morning evening bright calm deep gentle golden happy infinite jolly
    kind light mighty noble peaceful quiet radiant serene swift wise
    ancient brave clever bold cosmic elegant fierce crystal dancing
    electric frozen glowing misty mystic ocean silver storm sunset
    thunder winter stellar lunar royal emerald crimson azure violet
  ].freeze
  
  NOUNS = %w[
    forest mountain river ocean star moon dream whisper butterfly
    dragon phoenix eagle wolf bear lion tiger elephant dolphin
    whale turtle dove hawk falcon swan crystal diamond ruby
    emerald sapphire pearl jade amber opal castle tower bridge
    valley meadow garden waterfall lagoon island plateau canyon
    wisdom courage honor justice truth beauty grace strength harmony
  ].freeze
  
  def display_name
    SUPPORTED_DATABASES.dig(database_type, :name) || database_type&.capitalize
  end
  
  def redis_display_name
    return nil unless redis_enabled?
    "Redis (#{redis_name})"
  end
  
  def plugin_url
    SUPPORTED_DATABASES.dig(database_type, :plugin_url)
  end
  
  def redis_plugin_url
    REDIS_CONFIG[:plugin_url]
  end
  
  def environment_variable_name
    SUPPORTED_DATABASES.dig(database_type, :env_var)
  end
  
  def redis_environment_variable_name
    REDIS_CONFIG[:env_var]
  end
  
  def has_environment_variable_conflict?
    return [] unless deployment
    
    env_var_name = environment_variable_name
    redis_env_var_name = redis_environment_variable_name
    
    env_vars = deployment.environment_variables.pluck(:key)
    
    conflicts = []
    conflicts << env_var_name if env_var_name && env_vars.include?(env_var_name)
    conflicts << redis_env_var_name if redis_enabled? && redis_env_var_name && env_vars.include?(redis_env_var_name)
    
    conflicts
  end
  
  def status_text
    if error_message.present?
      "Configuration Failed"
    elsif configured?
      "Configured"
    else
      "Pending Configuration"
    end
  end
  
  def status_class
    if error_message.present?
      'bg-danger'
    elsif configured?
      'bg-success'
    else
      'bg-warning text-dark'
    end
  end
  
  def can_be_deleted?
    # Can delete if it's configured or if there was an error
    configured? || error_message.present?
  end
  
  def deletion_warning_message
    message = "This will permanently:"
    message += "\n• Detach the #{display_name} database (#{database_name}) from your app"
    message += "\n• Delete the database and all its data"
    message += "\n• Remove DATABASE_URL environment variable"
    
    if redis_enabled?
      message += "\n• Detach and delete the Redis instance (#{redis_name})"
      message += "\n• Remove REDIS_URL environment variable"
    end
    
    message += "\n\n⚠️ This action cannot be undone!"
    message
  end
  
  private
  
  def generate_database_name
    return if database_name.present?
    
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
      unless DatabaseConfiguration.exists?(database_name: generated_name)
        self.database_name = generated_name
        break
      end
      
    end while attempts < max_attempts
    
    # Fallback to timestamp-based name if we couldn't generate a unique one
    if database_name.blank?
      timestamp = Time.current.to_i
      self.database_name = "db-#{timestamp}"
    end
  end
  
  def generate_credentials
    # Generate random username and password
    self.username = SecureRandom.alphanumeric(12) if username.blank?
    self.password = SecureRandom.alphanumeric(16) if password.blank?
  end
  
  def generate_redis_name
    return unless redis_enabled?
    return if redis_name.present?
    
    # Generate Redis name based on database name
    self.redis_name = "#{database_name}-redis"
  end
  
  def check_environment_variable_conflict
    conflicts = has_environment_variable_conflict?
    
    if conflicts.any?
      errors.add(:base, "Environment variables already exist: #{conflicts.join(', ')}. Remove these environment variables to use managed databases.")
    end
  end
end
