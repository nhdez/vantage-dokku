# Application Settings Seeds
# This file contains all default app settings that can be loaded independently
# Usage: rails db:seed:app_settings

puts "Seeding Application Settings..."

# General Application Settings
AppSetting.set('app_name', 'Vantage', description: 'Application name displayed in navigation and emails', setting_type: 'string')
AppSetting.set('allow_registration', 'true', description: 'Allow new users to register accounts', setting_type: 'boolean')
AppSetting.set('require_email_confirmation', 'false', description: 'Require email confirmation for new accounts', setting_type: 'boolean')
AppSetting.set('maintenance_mode', 'false', description: 'Enable maintenance mode to restrict access', setting_type: 'boolean')
AppSetting.set('max_file_upload_size', '10', description: 'Maximum file upload size in MB', setting_type: 'integer')
AppSetting.set('default_user_role', 'registered', description: 'Default role assigned to new users', setting_type: 'string')

# Infrastructure Settings
AppSetting.set('dokku_install_version', '0.36.7', description: 'Default Dokku version to install on new servers', setting_type: 'string')
AppSetting.set('go_lang_version', 'go1.23.5', description: 'Latest Go Language version for server installations', setting_type: 'string')

puts "✓ Application Settings seeded successfully"
puts "  - General settings: 6 configured"
puts "  - Infrastructure settings: 2 configured"
