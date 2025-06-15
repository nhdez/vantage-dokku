require 'net/http'
require 'uri'
require 'timeout'

class ApplicationHealthService
  TIMEOUT_SECONDS = 10
  USER_AGENT = 'VantageDokku-HealthMonitor/1.0'
  
  def self.check_deployment(deployment)
    new(deployment).check_health
  end
  
  def self.check_all_deployments
    Deployment.joins(:server)
              .where(servers: { connection_status: 'connected' })
              .includes(:server, :domains)
              .find_each do |deployment|
      next unless deployment.dokku_url.present?
      check_deployment(deployment)
    end
  end
  
  def initialize(deployment)
    @deployment = deployment
  end
  
  def check_health
    return unless @deployment.dokku_url.present?
    
    url = @deployment.dokku_url
    
    Rails.logger.info "Checking health for #{@deployment.name} at #{url}"
    
    result = ping_url(url)
    save_health_check_result(result)
    cleanup_old_health_checks
    
    result
  rescue StandardError => e
    Rails.logger.error "Health check failed for #{@deployment.name}: #{e.message}"
    
    error_result = {
      status: 'error',
      response_code: nil,
      response_time: nil,
      response_body: "Error: #{e.message}",
      checked_at: Time.current
    }
    
    save_health_check_result(error_result)
    cleanup_old_health_checks
    
    error_result
  end
  
  private
  
  def ping_url(url_string)
    start_time = Time.current
    
    begin
      uri = URI.parse(url_string)
      
      # Ensure we have a scheme
      uri.scheme ||= 'http'
      
      # Create HTTP client
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE if http.use_ssl?
      http.read_timeout = TIMEOUT_SECONDS
      http.open_timeout = TIMEOUT_SECONDS
      
      # Create request
      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = USER_AGENT
      request['Accept'] = 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8'
      
      # Perform request with timeout
      response = Timeout::timeout(TIMEOUT_SECONDS) do
        http.request(request)
      end
      
      response_time = ((Time.current - start_time) * 1000).round(2) # Convert to milliseconds
      
      status = determine_status(response.code.to_i)
      
      {
        status: status,
        response_code: response.code.to_i,
        response_time: response_time,
        response_body: truncate_response_body(response.body),
        checked_at: Time.current
      }
      
    rescue Timeout::Error
      response_time = ((Time.current - start_time) * 1000).round(2)
      {
        status: 'timeout',
        response_code: nil,
        response_time: response_time,
        response_body: "Request timed out after #{TIMEOUT_SECONDS} seconds",
        checked_at: Time.current
      }
    rescue Net::HTTPError, SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
      response_time = ((Time.current - start_time) * 1000).round(2)
      {
        status: 'unhealthy',
        response_code: nil,
        response_time: response_time,
        response_body: "Connection error: #{e.message}",
        checked_at: Time.current
      }
    end
  end
  
  def determine_status(response_code)
    case response_code
    when 200..299
      'healthy'
    when 300..399
      'healthy' # Redirects are considered healthy
    when 400..499
      'unhealthy' # Client errors
    when 500..599
      'unhealthy' # Server errors
    else
      'error'
    end
  end
  
  def truncate_response_body(body)
    return nil if body.nil?
    
    # Limit response body to 1000 characters to avoid database bloat
    body.length > 1000 ? "#{body[0..996]}..." : body
  end
  
  def save_health_check_result(result)
    ApplicationHealth.create!(
      deployment: @deployment,
      status: result[:status],
      response_code: result[:response_code],
      response_time: result[:response_time],
      response_body: result[:response_body],
      checked_at: result[:checked_at]
    )
    
    Rails.logger.info "Health check saved for #{@deployment.name}: #{result[:status]} (#{result[:response_code]}) #{result[:response_time]}ms"
  rescue StandardError => e
    Rails.logger.error "Failed to save health check for #{@deployment.name}: #{e.message}"
  end
  
  def cleanup_old_health_checks
    # Keep only the last 20 health checks per deployment to prevent database bloat
    old_checks = @deployment.application_healths
                           .order(checked_at: :desc)
                           .offset(20)
    
    if old_checks.any?
      deleted_count = old_checks.delete_all
      Rails.logger.debug "Cleaned up #{deleted_count} old health checks for #{@deployment.name}"
    end
  end
end