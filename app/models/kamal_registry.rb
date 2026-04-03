class KamalRegistry < ApplicationRecord
  belongs_to :kamal_configuration

  COMMON_REGISTRIES = [
    "ghcr.io",
    "docker.io",
    "registry.gitlab.com"
  ].freeze

  SELF_HOSTED_PORT = 5000

  encrypts :password, deterministic: false

  validates :registry_server, presence: true
  validates :username, presence: true, unless: :self_hosted?
  validates :password, presence: true, unless: :self_hosted?

  def self_hosted?
    self_hosted
  end

  def display_name
    self_hosted? ? "Self-hosted (#{registry_server})" : "#{registry_server} (#{username})"
  end

  def image_for(service_name)
    if self_hosted?
      "#{registry_server}/#{service_name}"
    else
      "#{registry_server}/#{username}/#{service_name}"
    end
  end
end
