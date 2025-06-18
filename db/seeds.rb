# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create default roles
["admin", "mod", "registered"].each do |role_name|
  Role.find_or_create_by!(name: role_name)
end

puts "Created default roles: admin, mod, registered"

# Create default app settings
AppSetting.set('app_name', 'Vantage', description: 'Application name displayed in navigation and emails', setting_type: 'string')
AppSetting.set('allow_registration', 'true', description: 'Allow new users to register accounts', setting_type: 'boolean')
AppSetting.set('require_email_confirmation', 'false', description: 'Require email confirmation for new accounts', setting_type: 'boolean')
AppSetting.set('maintenance_mode', 'false', description: 'Enable maintenance mode to restrict access', setting_type: 'boolean')
AppSetting.set('max_file_upload_size', '10', description: 'Maximum file upload size in MB', setting_type: 'integer')
AppSetting.set('default_user_role', 'registered', description: 'Default role assigned to new users', setting_type: 'string')
AppSetting.set('dokku_install_version', '0.35.9', description: 'Default Dokku version to install on new servers', setting_type: 'string')

puts "Created default app settings"

# Create default OAuth settings
OauthSetting.setup_defaults!
puts "Created default OAuth settings"

# Create a default admin user if none exists
if User.where(email: "admin@example.com").empty?
  admin_user = User.create!(
    email: "admin@example.com",
    password: "password123",
    password_confirmation: "password123",
    first_name: "System",
    last_name: "Administrator"
  )
  admin_user.add_role(:admin)
  puts "Created admin user: admin@example.com (password: password123)"
end
