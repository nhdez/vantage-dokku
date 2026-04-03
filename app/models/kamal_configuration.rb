class KamalConfiguration < ApplicationRecord
  belongs_to :deployment
  has_one :kamal_registry, dependent: :destroy
  has_many :kamal_accessories, dependent: :destroy
  has_many :kamal_servers, dependent: :destroy
  has_many :servers, through: :kamal_servers

  BUILDER_ARCHS = %w[local amd64 arm64 multiarch].freeze
  ACCESSORY_STATUSES = %w[pending booting running failed].freeze

  validates :builder_arch, inclusion: { in: BUILDER_ARCHS }
  validates :proxy_app_port, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65535 }, allow_nil: true
  validates :healthcheck_port, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65535 }, allow_nil: true
  validates :builder_remote, presence: true, if: -> { builder_arch.in?(%w[multiarch]) }

  def configured?
    configured
  end

  def web_servers
    kamal_servers.where(role: "web").includes(:server)
  end

  def primary_server
    kamal_servers.find_by(primary: true)&.server
  end

  def worker_servers
    kamal_servers.where(role: "worker").includes(:server)
  end

  def has_registry?
    kamal_registry.present?
  end

  def has_web_server?
    kamal_servers.where(role: "web").any?
  end

  def status_text
    if configured?
      "Configured"
    elsif error_message.present?
      "Error"
    else
      "Pending configuration"
    end
  end

  def status_class
    if configured?
      "bg-success"
    elsif error_message.present?
      "bg-danger"
    else
      "bg-warning text-dark"
    end
  end
end
