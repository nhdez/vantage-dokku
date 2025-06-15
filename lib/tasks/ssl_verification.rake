namespace :ssl do
  desc "Test SSL verification for a domain"
  task :verify, [:domain_name] => :environment do |t, args|
    domain_name = args[:domain_name]
    
    if domain_name.blank?
      puts "Usage: rails ssl:verify[domain.com]"
      exit 1
    end
    
    puts "Verifying SSL for domain: #{domain_name}"
    puts "=" * 50
    
    result = SslVerificationService.verify_domain_ssl(domain_name)
    
    puts "Domain: #{result[:domain]}"
    puts "HTTP Accessible: #{result[:http_accessible] ? 'Yes' : 'No'}"
    puts "HTTPS Accessible: #{result[:https_accessible] ? 'Yes' : 'No'}"
    puts "SSL Active: #{result[:ssl_active] ? 'Yes' : 'No'}"
    puts "SSL Valid: #{result[:ssl_valid] ? 'Yes' : 'No'}"
    puts "Response Time: #{result[:response_time]}ms" if result[:response_time]
    puts "Checked At: #{result[:checked_at]}"
    
    if result[:error_message]
      puts "Error: #{result[:error_message]}"
    end
    
    if result[:ssl_certificate_info]
      cert = result[:ssl_certificate_info]
      puts "\nSSL Certificate Info:"
      puts "  Subject: #{cert[:subject]}"
      puts "  Issuer: #{cert[:issuer]}"
      puts "  Valid From: #{cert[:not_before]}"
      puts "  Valid Until: #{cert[:not_after]}"
      puts "  Days Until Expiry: #{cert[:days_until_expiry]}"
      puts "  Expired: #{cert[:expired] ? 'Yes' : 'No'}"
    end
  end
  
  desc "Verify SSL for all domains in the database"
  task verify_all: :environment do
    puts "Verifying SSL for all domains..."
    puts "=" * 50
    
    Domain.includes(:deployment).each do |domain|
      puts "\nChecking: #{domain.name} (#{domain.deployment.name})"
      
      result = domain.verify_ssl_status
      status_text = domain.real_ssl_status_text
      status_color = domain.real_ssl_status_color
      
      case status_color
      when 'success'
        puts "  ✅ #{status_text}"
      when 'warning'
        puts "  ⚠️  #{status_text}"
      when 'danger'
        puts "  ❌ #{status_text}"
      else
        puts "  ❓ #{status_text}"
      end
      
      if domain.ssl_response_time
        puts "    Response time: #{domain.ssl_response_time}ms"
      end
      
      if domain.ssl_verification_error
        puts "    Error: #{domain.ssl_verification_error}"
      end
    end
    
    puts "\nSummary:"
    total_domains = Domain.count
    healthy_domains = Domain.select { |d| d.ssl_actually_working? }.count
    puts "Total domains: #{total_domains}"
    puts "Healthy SSL: #{healthy_domains}"
    puts "Success rate: #{total_domains > 0 ? ((healthy_domains.to_f / total_domains) * 100).round(1) : 0}%"
  end
  
  desc "Show SSL statistics"
  task stats: :environment do
    puts "SSL Status Statistics"
    puts "=" * 30
    
    total_domains = Domain.count
    puts "Total domains: #{total_domains}"
    
    if total_domains > 0
      statuses = Domain.all.map(&:real_ssl_status_text)
      
      status_counts = statuses.group_by(&:itself).transform_values(&:count)
      
      status_counts.each do |status, count|
        percentage = ((count.to_f / total_domains) * 100).round(1)
        puts "#{status}: #{count} (#{percentage}%)"
      end
      
      healthy_count = Domain.select(&:ssl_actually_working?).count
      puts "\nOverall SSL health: #{((healthy_count.to_f / total_domains) * 100).round(1)}%"
    end
  end
end