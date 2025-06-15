require 'net/http'
require 'uri'
require 'openssl'
require 'timeout'

class SslVerificationService
  TIMEOUT_SECONDS = 10
  USER_AGENT = 'VantageDokku-SSLChecker/1.0'
  
  def self.verify_domain_ssl(domain)
    new(domain).verify_ssl
  end
  
  def self.verify_all_domains
    Domain.all.map do |domain|
      {
        domain: domain,
        ssl_status: verify_domain_ssl(domain)
      }
    end
  end
  
  def initialize(domain)
    @domain = domain
    @domain_name = domain.is_a?(String) ? domain : domain.name
  end
  
  def verify_ssl
    Rails.logger.info "Verifying SSL for domain: #{@domain_name}"
    
    result = {
      domain: @domain_name,
      ssl_active: false,
      ssl_valid: false,
      https_accessible: false,
      http_accessible: false,
      ssl_certificate_info: nil,
      error_message: nil,
      response_time: nil,
      checked_at: Time.current
    }
    
    # First check if domain is accessible via HTTP
    http_result = check_http_connectivity
    result.merge!(http_result)
    
    # Then check HTTPS/SSL
    if result[:http_accessible]
      https_result = check_https_connectivity
      result.merge!(https_result)
      
      # If HTTPS works, get certificate details
      if result[:https_accessible]
        cert_result = get_certificate_info
        result.merge!(cert_result)
      end
    end
    
    result
  rescue StandardError => e
    Rails.logger.error "SSL verification failed for #{@domain_name}: #{e.message}"
    
    {
      domain: @domain_name,
      ssl_active: false,
      ssl_valid: false,
      https_accessible: false,
      http_accessible: false,
      ssl_certificate_info: nil,
      error_message: "Verification error: #{e.message}",
      response_time: nil,
      checked_at: Time.current
    }
  end
  
  private
  
  def check_http_connectivity
    start_time = Time.current
    
    begin
      uri = URI("http://#{@domain_name}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.read_timeout = TIMEOUT_SECONDS
      http.open_timeout = TIMEOUT_SECONDS
      
      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = USER_AGENT
      
      response = Timeout::timeout(TIMEOUT_SECONDS) do
        http.request(request)
      end
      
      response_time = ((Time.current - start_time) * 1000).round(2)
      
      {
        http_accessible: true,
        http_response_code: response.code.to_i,
        response_time: response_time
      }
      
    rescue Timeout::Error
      response_time = ((Time.current - start_time) * 1000).round(2)
      {
        http_accessible: false,
        error_message: "HTTP timeout after #{TIMEOUT_SECONDS}s",
        response_time: response_time
      }
    rescue => e
      response_time = ((Time.current - start_time) * 1000).round(2)
      {
        http_accessible: false,
        error_message: "HTTP error: #{e.message}",
        response_time: response_time
      }
    end
  end
  
  def check_https_connectivity
    start_time = Time.current
    
    begin
      uri = URI("https://#{@domain_name}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.read_timeout = TIMEOUT_SECONDS
      http.open_timeout = TIMEOUT_SECONDS
      
      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = USER_AGENT
      
      response = Timeout::timeout(TIMEOUT_SECONDS) do
        http.request(request)
      end
      
      https_response_time = ((Time.current - start_time) * 1000).round(2)
      
      {
        https_accessible: true,
        ssl_active: true,
        ssl_valid: true,
        https_response_code: response.code.to_i,
        https_response_time: https_response_time
      }
      
    rescue OpenSSL::SSL::SSLError => e
      https_response_time = ((Time.current - start_time) * 1000).round(2)
      {
        https_accessible: false,
        ssl_active: true,  # SSL is present but invalid
        ssl_valid: false,
        error_message: "SSL error: #{e.message}",
        https_response_time: https_response_time
      }
    rescue Timeout::Error
      https_response_time = ((Time.current - start_time) * 1000).round(2)
      {
        https_accessible: false,
        ssl_active: false,
        error_message: "HTTPS timeout after #{TIMEOUT_SECONDS}s",
        https_response_time: https_response_time
      }
    rescue => e
      https_response_time = ((Time.current - start_time) * 1000).round(2)
      {
        https_accessible: false,
        ssl_active: false,
        error_message: "HTTPS error: #{e.message}",
        https_response_time: https_response_time
      }
    end
  end
  
  def get_certificate_info
    begin
      socket = TCPSocket.new(@domain_name, 443)
      ssl_context = OpenSSL::SSL::SSLContext.new
      ssl_context.verify_mode = OpenSSL::SSL::VERIFY_NONE  # Just get cert info, don't verify
      ssl_socket = OpenSSL::SSL::SSLSocket.new(socket, ssl_context)
      
      Timeout::timeout(TIMEOUT_SECONDS) do
        ssl_socket.connect
      end
      
      cert = ssl_socket.peer_cert
      
      cert_info = {
        ssl_certificate_info: {
          subject: cert.subject.to_s,
          issuer: cert.issuer.to_s,
          not_before: cert.not_before,
          not_after: cert.not_after,
          expired: cert.not_after < Time.current,
          days_until_expiry: ((cert.not_after - Time.current) / 1.day).round,
          serial_number: cert.serial.to_s,
          signature_algorithm: cert.signature_algorithm
        }
      }
      
      ssl_socket.close
      socket.close
      
      cert_info
      
    rescue => e
      Rails.logger.error "Failed to get certificate info for #{@domain_name}: #{e.message}"
      {
        ssl_certificate_info: nil,
        error_message: "Certificate check failed: #{e.message}"
      }
    end
  end
end