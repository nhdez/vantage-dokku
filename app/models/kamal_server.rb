class KamalServer < ApplicationRecord
  belongs_to :kamal_configuration
  belongs_to :server

  ROLES = %w[web worker cron].freeze

  validates :role, inclusion: { in: ROLES }
  validates :server_id, uniqueness: {
    scope: [ :kamal_configuration_id, :role ],
    message: "is already assigned to this role in this deployment"
  }
  validate :server_must_be_connected
  validate :only_one_primary_web_server, if: -> { primary? && role == "web" }

  scope :web, -> { where(role: "web") }
  scope :workers, -> { where(role: "worker") }
  scope :cron, -> { where(role: "cron") }
  scope :primary, -> { where(primary: true) }

  def docker_ready?
    server.docker_installed?
  end

  private

  def server_must_be_connected
    return unless server.present?

    unless server.connected?
      errors.add(:server, "must be connected before being added to a Kamal deployment")
    end
  end

  def only_one_primary_web_server
    existing = kamal_configuration.kamal_servers
                                  .where(role: "web", primary: true)
                                  .where.not(id: id)
    if existing.any?
      errors.add(:primary, "web server is already set — unset the current primary first")
    end
  end
end
