class PortMapping < ApplicationRecord
  belongs_to :deployment

  validates :scheme, presence: true, inclusion: { in: %w[http https], message: "must be http or https" }
  validates :host_port, presence: true, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65535 }
  validates :container_port, presence: true, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65535 }
  validates :host_port, uniqueness: { scope: [:deployment_id, :scheme, :container_port], message: "mapping already exists" }

  scope :ordered, -> { order(:scheme, :host_port) }

  def display_name
    "#{scheme}:#{host_port}:#{container_port}"
  end

  def to_dokku_format
    "#{scheme}:#{host_port}:#{container_port}"
  end
end
