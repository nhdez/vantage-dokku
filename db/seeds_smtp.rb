# Add SMTP settings to the database
puts "Adding SMTP settings..."

AppSetting.set('smtp_enabled', 'false', description: 'Enable SMTP email delivery (disable for letter_opener in development)', setting_type: 'boolean')
AppSetting.set('smtp_address', ENV['SMTP_ADDRESS'] || 'email-smtp.us-east-1.amazonaws.com', description: 'SMTP server address', setting_type: 'string')
AppSetting.set('smtp_port', ENV['SMTP_PORT'] || '587', description: 'SMTP server port', setting_type: 'integer')
AppSetting.set('smtp_domain', ENV['SMTP_DOMAIN'] || '', description: 'SMTP domain', setting_type: 'string')
AppSetting.set('smtp_username', ENV['SMTP_USERNAME'] || '', description: 'SMTP username/access key', setting_type: 'string')
AppSetting.set('smtp_password', ENV['SMTP_PASSWORD'] || '', description: 'SMTP password/secret key', setting_type: 'string')
AppSetting.set('smtp_authentication', ENV['SMTP_AUTHENTICATION'] || 'plain', description: 'SMTP authentication method', setting_type: 'string')
AppSetting.set('mail_from', ENV['MAIL_FROM'] || 'no-reply@example.com', description: 'Default from email address', setting_type: 'string')

puts "SMTP settings created successfully!"