require "yaml"
require "fileutils"

# Generates a valid Kamal 2 config/deploy.yml and .kamal/secrets from a
# KamalConfiguration record.  The files are written to a per-deployment temp
# directory so multiple concurrent operations can coexist safely.
class KamalConfigGenerator
  SECRETS_FILE_PERMISSIONS = 0o600

  def initialize(kamal_configuration)
    @config    = kamal_configuration
    @deploy    = kamal_configuration.deployment
    @registry  = kamal_configuration.kamal_registry
    @servers   = kamal_configuration.kamal_servers.includes(:server)
    @accessories = kamal_configuration.kamal_accessories
    @env_vars  = @deploy.environment_variables.ordered
  end

  # Returns the generated deploy.yml as a YAML string.
  def deploy_yml
    YAML.dump(build_config_hash).gsub(/\A---\n/, "")
  end

  # Returns the .kamal/secrets file content — actual secret values.
  # NEVER log or display the return value of this method.
  def secrets_file
    lines = []
    lines << "KAMAL_REGISTRY_PASSWORD=#{@registry&.password}" unless @registry&.self_hosted?
    secret_env_vars.each { |ev| lines << "#{ev.key}=#{ev.value}" }
    accessory_secret_keys.each { |key| lines << "#{key}=" }
    lines.join("\n") + "\n"
  end

  # Returns a secrets file with all values replaced by [REDACTED].
  # Safe to render in UI.
  def secrets_template
    lines = []
    lines << "KAMAL_REGISTRY_PASSWORD=[REDACTED]" unless @registry&.self_hosted?
    secret_env_vars.each { |ev| lines << "#{ev.key}=[REDACTED]" }
    accessory_secret_keys.each { |key| lines << "#{key}=[REDACTED]" }
    lines.join("\n") + "\n"
  end

  # Temp directory for this deployment's Kamal config files.
  def config_dir_path
    Rails.root.join("tmp", "kamal", @deploy.uuid)
  end

  # Writes deploy.yml and .kamal/secrets to config_dir_path with correct perms.
  def write_config_files!
    kamal_dir = config_dir_path.join(".kamal")
    FileUtils.mkdir_p(config_dir_path)
    FileUtils.mkdir_p(kamal_dir)

    deploy_yml_path = config_dir_path.join("deploy.yml")
    File.write(deploy_yml_path, deploy_yml)

    secrets_path = kamal_dir.join("secrets")
    File.write(secrets_path, secrets_file)
    File.chmod(SECRETS_FILE_PERMISSIONS, secrets_path)

    self
  end

  # Removes the temp directory for this deployment.
  def cleanup!
    FileUtils.rm_rf(config_dir_path)
  end

  # True if the minimum required fields are present to generate a valid config.
  def valid_for_generation?
    @config.service_name.present? &&
      @config.image.present? &&
      @registry.present? &&
      @servers.web.any?
  end

  # Returns an array of human-readable strings describing missing config.
  def missing_fields
    issues = []
    issues << "Service name is required"       if @config.service_name.blank?
    issues << "Docker image is required"       if @config.image.blank?
    issues << "Registry credentials required"  unless @registry.present?
    issues << "At least one web server required" unless @servers.web.any?
    issues << "Primary domain required for SSL" if @config.proxy_ssl && @config.proxy_host.blank?
    issues
  end

  private

  # ─── Config hash ────────────────────────────────────────────────────────────

  def build_config_hash
    hash = {}
    hash["service"] = @config.service_name if @config.service_name.present?
    hash["image"]   = @config.image if @config.image.present?
    hash["servers"] = servers_section
    hash["registry"] = registry_section if @registry.present?
    hash["env"] = env_section unless @env_vars.empty?
    hash["builder"] = builder_section
    hash["proxy"] = proxy_section
    hash["healthcheck"] = healthcheck_section
    hash["asset_path"] = @config.asset_path if @config.asset_path.present?
    hash["accessories"] = accessories_section if @accessories.any?
    hash
  end

  def servers_section
    grouped = @servers.group_by(&:role)
    section = {}

    if (web = grouped["web"])
      section["web"] = web_role_hash(web)
    end

    %w[worker cron].each do |role|
      next unless grouped[role]

      section[role] = worker_role_hash(grouped[role])
    end

    section
  end

  def web_role_hash(kamal_servers)
    hosts = kamal_servers.map { |ks| ks.server.ip }
    hash = { "hosts" => hosts }
    first = kamal_servers.first
    hash["options"] = { "stop-wait-time" => first.stop_wait_time } if first.stop_wait_time.present?
    hash["options"] = (hash["options"] || {}).merge(first.docker_options) if first.docker_options.present?
    hash
  end

  def worker_role_hash(kamal_servers)
    hosts = kamal_servers.map { |ks| ks.server.ip }
    hash = { "hosts" => hosts }
    first = kamal_servers.first
    hash["cmd"] = first.cmd if first.cmd.present?
    hash["options"] = { "stop-wait-time" => first.stop_wait_time } if first.stop_wait_time.present?
    hash
  end

  def registry_section
    if @registry.self_hosted?
      { "server" => @registry.registry_server }
    else
      {
        "server"   => @registry.registry_server,
        "username" => @registry.username,
        "password" => [ "KAMAL_REGISTRY_PASSWORD" ]
      }
    end
  end

  def env_section
    clear_vars  = clear_env_vars
    secret_vars = secret_env_vars

    section = {}
    section["clear"]  = clear_vars.each_with_object({}) { |ev, h| h[ev.key] = ev.value } if clear_vars.any?
    section["secret"] = secret_vars.map(&:key) if secret_vars.any?
    section
  end

  def builder_section
    hash = { "arch" => @config.builder_arch }
    hash["remote"] = @config.builder_remote if @config.builder_remote.present?
    hash
  end

  def proxy_section
    hash = {
      "ssl"              => @config.proxy_ssl,
      "app_port"         => @config.proxy_app_port,
      "response_timeout" => @config.proxy_response_timeout,
      "forward_headers"  => @config.proxy_forward_headers
    }
    hash["host"] = @config.proxy_host if @config.proxy_host.present?

    if @config.proxy_buffering
      hash["buffering"] = {
        "enabled"          => true,
        "max_request_body" => @config.proxy_max_body_size.presence || "10m"
      }
    end

    hash
  end

  def healthcheck_section
    hash = { "path" => (@config.healthcheck_path.presence || "/up") }
    hash["port"] = @config.healthcheck_port if @config.healthcheck_port.present?
    hash
  end

  def accessories_section
    @accessories.each_with_object({}) do |acc, hash|
      acc_hash = {
        "image" => acc.image,
        "host"  => acc.host,
        "port"  => acc.port
      }.compact

      env_keys = acc.env_vars.keys
      clear_keys = env_keys.reject { |k| k.match?(/password|secret|key|token/i) }
      secret_keys = env_keys.select { |k| k.match?(/password|secret|key|token/i) }

      env_block = {}
      env_block["clear"]  = acc.env_vars.slice(*clear_keys)  if clear_keys.any?
      env_block["secret"] = secret_keys if secret_keys.any?
      acc_hash["env"] = env_block unless env_block.empty?

      acc_hash["volumes"] = acc.volumes if acc.volumes.any?
      hash[acc.name] = acc_hash
    end
  end

  # ─── Helpers ────────────────────────────────────────────────────────────────

  def clear_env_vars
    @env_vars.reject { |ev| kamal_secret?(ev) }
  end

  def secret_env_vars
    @env_vars.select { |ev| kamal_secret?(ev) }
  end

  # Use the explicit `secret` column when available, fall back to heuristic
  def kamal_secret?(env_var)
    env_var.respond_to?(:secret) ? env_var.secret : env_var.sensitive?
  end

  def accessory_secret_keys
    @accessories.flat_map do |acc|
      acc.env_vars.keys.select { |k| k.match?(/password|secret|key|token/i) }
    end.uniq
  end
end
