class TestMailer < ApplicationMailer
  def test_email(to_email)
    @greeting = "Hello from Vantage!"
    @app_name = AppSetting.get('app_name', 'Vantage')
    @current_time = Time.current.strftime("%B %d, %Y at %I:%M %p")
    
    # Check if environment variables are fully configured
    required_env_vars = %w[USE_REAL_EMAIL SMTP_ADDRESS SMTP_PORT SMTP_DOMAIN SMTP_USERNAME SMTP_PASSWORD SMTP_AUTHENTICATION MAIL_FROM]
    env_fully_configured = required_env_vars.all? { |var| ENV[var].present? }
    
    if env_fully_configured
      @smtp_enabled = ENV['USE_REAL_EMAIL']&.downcase == 'true'
      from_address = ENV['MAIL_FROM'] || 'no-reply@example.com'
    else
      @smtp_enabled = AppSetting.get('smtp_enabled', false)
      from_address = AppSetting.get('mail_from', 'no-reply@example.com')
    end

    mail(
      to: to_email,
      subject: "Test Email from #{@app_name}",
      from: from_address
    )
  end
end
