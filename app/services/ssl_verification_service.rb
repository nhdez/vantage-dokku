require "net/http"
require "uri"
require "openssl"
require "timeout"

class SslVerificationService
  TIMEOUT_SECONDS = 10
  USER_AGENT = "VantageDokku-SSLChecker/1.0"

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
      request["User-Agent"] = USER_AGENT

      response = Timeout.timeout(TIMEOUT_SECONDS) do
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
      request["User-Agent"] = USER_AGENT

      response = Timeout.timeout(TIMEOUT_SECONDS) do
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

      Timeout.timeout(TIMEOUT_SECONDS) do
        ssl_socket.connect
      end

      cert = ssl_socket.peer_cert

      # Extract the common name and SANs from the certificate
      common_name = nil
      subject_alt_names = []

      cert.subject.each do |name, value|
        common_name = value if name[0] == "CN"
      end

      # Get Subject Alternative Names (SANs)
      begin
        cert.extensions.each do |ext|
          if ext.oid == "subjectAltName"
            # Parse the SAN extension
            san_string = ext.value
            # Extract DNS names from the SAN string
            san_string.scan(/DNS:([^,\s]+)/).each do |match|
              subject_alt_names << match[0]
            end
          end
        end
      rescue => e
        Rails.logger.warn "Failed to parse SANs: #{e.message}"
      end

      # Check if the requested domain matches any of the certificate domains
      all_cert_domains = [ common_name, *subject_alt_names ].compact.uniq
      domain_matches = all_cert_domains.any? do |cert_domain|
        # Check for exact match or wildcard match
        if cert_domain.start_with?("*.")
          # Wildcard certificate
          wildcard_base = cert_domain[2..-1]
          @domain_name.end_with?(wildcard_base) && @domain_name.count(".") == cert_domain.count(".")
        else
          # Exact match
          cert_domain.downcase == @domain_name.downcase
        end
      end

      cert_info = {
        ssl_certificate_info: {
          subject: cert.subject.to_s,
          common_name: common_name,
          subject_alt_names: subject_alt_names,
          all_domains: all_cert_domains,
          domain_matches: domain_matches,
          issuer: cert.issuer.to_s,
          not_before: cert.not_before,
          not_after: cert.not_after,
          expired: cert.not_after < Time.current,
          days_until_expiry: ((cert.not_after - Time.current) / 1.day).round,
          serial_number: cert.serial.to_s,
          signature_algorithm: cert.signature_algorithm
        }
      }

      # If domain doesn't match, update the error message
      unless domain_matches
        cert_info[:error_message] = "Certificate hostname mismatch: Certificate is for #{all_cert_domains.join(', ')} but requested domain is #{@domain_name}"
        cert_info[:ssl_valid] = false
      end

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
