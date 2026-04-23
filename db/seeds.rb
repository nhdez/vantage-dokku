# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Create default roles
[ "admin", "mod", "registered" ].each do |role_name|
  Role.find_or_create_by!(name: role_name)
end

puts "Created default roles: admin, mod, registered"

# Load app settings from separate seed file
load(Rails.root.join('db', 'seeds', 'app_settings.rb'))

# Create default OAuth settings
OauthSetting.setup_defaults!
puts "Created default OAuth settings"

# Create a default admin user in development only, driven by ENV vars.
# Set ADMIN_EMAIL and ADMIN_PASSWORD before running db:seed.
# Never run db:seed in production — manage admin accounts through the UI.
if Rails.env.development?
  admin_email    = ENV.fetch("ADMIN_EMAIL", "admin@example.com")
  admin_password = ENV.fetch("ADMIN_PASSWORD") { raise "Set ADMIN_PASSWORD env var before seeding" }

  unless User.exists?(email: admin_email)
    admin_user = User.create!(
      email: admin_email,
      password: admin_password,
      password_confirmation: admin_password,
      first_name: "System",
      last_name: "Administrator"
    )
    admin_user.add_role(:admin)
    puts "Created admin user: #{admin_email}"
  end
end
