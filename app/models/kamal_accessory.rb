class KamalAccessory < ApplicationRecord
  belongs_to :kamal_configuration

  STATUSES = %w[pending booting running failed].freeze

  PRESETS = {
    "postgres" => { image: "postgres:16", port: 5432, env_keys: %w[POSTGRES_PASSWORD POSTGRES_DB] },
    "mysql"    => { image: "mysql:8.0",    port: 3306, env_keys: %w[MYSQL_ROOT_PASSWORD MYSQL_DATABASE] },
    "mariadb"  => { image: "mariadb:11",   port: 3306, env_keys: %w[MARIADB_ROOT_PASSWORD] },
    "redis"    => { image: "redis:7",      port: 6379, env_keys: [] },
    "mongo"    => { image: "mongo:7",      port: 27017, env_keys: %w[MONGO_INITDB_ROOT_USERNAME MONGO_INITDB_ROOT_PASSWORD] }
  }.freeze

  validates :name, presence: true,
            format: { with: /\A[a-z0-9_-]+\z/, message: "must contain only lowercase letters, numbers, hyphens, and underscores" }
  validates :name, uniqueness: { scope: :kamal_configuration_id }
  validates :image, presence: true
  validates :status, inclusion: { in: STATUSES }

  def running?
    status == "running"
  end

  def pending?
    status == "pending"
  end

  def status_text
    status.humanize
  end

  def status_class
    case status
    when "running" then "bg-success"
    when "booting" then "bg-warning text-dark"
    when "failed"  then "bg-danger"
    else "bg-secondary"
    end
  end
end
