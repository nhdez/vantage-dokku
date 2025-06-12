class TestMailer < ApplicationMailer
  def test_email(to_email)
    @greeting = "Hello from Vantage!"
    @app_name = AppSetting.get('app_name', 'Vantage')
    @current_time = Time.current.strftime("%B %d, %Y at %I:%M %p")
    @smtp_enabled = AppSetting.get('smtp_enabled', false)

    mail(
      to: to_email,
      subject: "Test Email from #{@app_name}",
      from: AppSetting.get('mail_from', 'no-reply@example.com')
    )
  end
end
