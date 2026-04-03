class KamalRegistry < ApplicationRecord
  belongs_to :kamal_configuration

  COMMON_REGISTRIES = [
    "ghcr.io",
    "docker.io",
    "registry.gitlab.com"
  ].freeze

  encrypts :password, deterministic: false

  validates :registry_server, presence: true
  validates :username, presence: true
  validates :password, presence: true

  def display_name
    "#{registry_server} (#{username})"
  end

  def image_for(service_name)
    "#{registry_server}/#{username}/#{service_name}"
  end
end
