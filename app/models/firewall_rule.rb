class FirewallRule < ApplicationRecord
  belongs_to :server

  validates :action, presence: true, inclusion: { in: %w[allow deny limit reject], message: "must be allow, deny, limit, or reject" }
  validates :direction, presence: true, inclusion: { in: %w[in out], message: "must be in or out" }
  validates :protocol, inclusion: { in: %w[tcp udp any], message: "must be tcp, udp, or any" }, allow_blank: true
  validates :port, format: { with: /\A\d+(:\d+)?(\/\w+)?\z/, message: "must be a valid port or port range (e.g., 80, 8000:9000)" }, allow_blank: true

  scope :ordered, -> { order(Arel.sql("position IS NULL, position ASC, created_at ASC")) }
  scope :enabled, -> { where(enabled: true) }

  before_create :set_position

  ACTIONS = %w[allow deny limit reject].freeze
  DIRECTIONS = %w[in out].freeze
  PROTOCOLS = %w[tcp udp any].freeze

  # Common predefined rules
  COMMON_RULES = {
    "SSH" => { port: "22", protocol: "tcp", action: "allow", direction: "in", comment: "Allow SSH access" },
    "HTTP" => { port: "80", protocol: "tcp", action: "allow", direction: "in", comment: "Allow HTTP traffic" },
    "HTTPS" => { port: "443", protocol: "tcp", action: "allow", direction: "in", comment: "Allow HTTPS traffic" },
    "PostgreSQL" => { port: "5432", protocol: "tcp", action: "allow", direction: "in", comment: "Allow PostgreSQL" },
    "MySQL" => { port: "3306", protocol: "tcp", action: "allow", direction: "in", comment: "Allow MySQL/MariaDB" },
    "Redis" => { port: "6379", protocol: "tcp", action: "allow", direction: "in", comment: "Allow Redis" },
    "MongoDB" => { port: "27017", protocol: "tcp", action: "allow", direction: "in", comment: "Allow MongoDB" }
  }.freeze

  def display_name
    parts = []
    parts << action.upcase
    parts << direction.upcase
    parts << "#{protocol.upcase}/" if protocol.present?
    parts << port if port.present?
    parts << "from #{from_ip}" if from_ip.present?
    parts << "to #{to_ip}" if to_ip.present?
    parts.join(" ")
  end

  def to_ufw_command
    cmd = "ufw #{action}"
    cmd += " #{direction}" if direction.present?
    cmd += " proto #{protocol}" if protocol.present? && protocol != "any"

    if direction == "in"
      cmd += " from #{from_ip || 'any'}"
      cmd += " to #{to_ip || 'any'}"
    elsif direction == "out"
      cmd += " from #{from_ip || 'any'}"
      cmd += " to #{to_ip || 'any'}"
    end

    cmd += " port #{port}" if port.present?
    cmd += " comment '#{comment}'" if comment.present?
    cmd
  end

  private

  def set_position
    self.position = server.firewall_rules.maximum(:position).to_i + 1 if position.nil?
  end
end
