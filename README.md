# Vantage Dokku

A Rails 8 application for managing Dokku PaaS deployments. Deploy and manage multiple applications across your Dokku servers with a clean web interface.

## Features

- 🚀 **Multi-server Management** - Manage multiple Dokku servers from one dashboard
- 🔧 **App Deployment** - Deploy applications with Git integration
- 🔒 **SSL Management** - Automatic Let's Encrypt SSL certificates
- 📊 **Database Configuration** - PostgreSQL, MySQL, MariaDB, MongoDB, Redis support
- 🔑 **SSH Key Management** - Manage deployment keys per application
- 🌐 **Domain Management** - Configure custom domains with SSL
- 📝 **Environment Variables** - Manage app configuration
- 📈 **Real-time Updates** - Live status updates via ActionCable

## Requirements

- Ruby 3.3+
- PostgreSQL
- Redis (optional, for production ActionCable)
- A Dokku server to manage

## Local Development

```bash
# Clone and setup
git clone https://github.com/yourusername/vantage-dokku.git
cd vantage-dokku
bundle install
rails db:create db:migrate

# Configure environment
cp .env.example .env
# Edit .env with your settings

# Start the server
bin/dev
```

## Production Deployment on Dokku

### 1. Prepare Your Dokku Server

```bash
# Create the app
dokku apps:create your-app-name

# Add PostgreSQL
dokku plugin:install https://github.com/dokku/dokku-postgres.git
dokku postgres:create your-app-name-db
dokku postgres:link your-app-name-db your-app-name
```

### 2. Configure Environment Variables

```bash
# Required variables
dokku config:set your-app-name \
  RAILS_ENV=production \
  SECRET_KEY_BASE=$(openssl rand -hex 64) \
  APP_HOST=yourdomain.com \
  DOKKU_LETSENCRYPT_EMAIL=admin@yourdomain.com

# Optional: OAuth (if using Google login)
dokku config:set your-app-name \
  GOOGLE_CLIENT_ID=your-client-id \
  GOOGLE_CLIENT_SECRET=your-client-secret

# Optional: SMTP (for email notifications)
dokku config:set your-app-name \
  SMTP_ADDRESS=smtp.gmail.com \
  SMTP_PORT=587 \
  SMTP_USERNAME=your-email@gmail.com \
  SMTP_PASSWORD=your-app-password \
  SMTP_FROM_EMAIL=noreply@yourdomain.com
```

### 3. Deploy the Application

```bash
# Add Dokku as a git remote
git remote add dokku dokku@your-server:your-app-name

# Deploy
git push dokku main

# Scale the workers (IMPORTANT!)
dokku ps:scale your-app-name web=1 worker=1
```

### 4. Post-Deployment Setup

```bash
# Run database migrations
dokku run your-app-name rails db:migrate

# Create SolidQueue and SolidCable tables
dokku run your-app-name rails runner "load Rails.root.join('db', 'queue_schema.rb')"
dokku run your-app-name rails runner "load Rails.root.join('db', 'cable_schema.rb')"

# Create admin user
dokku run your-app-name rails console
# Then in console:
# User.create!(email: 'admin@example.com', password: 'your-password', admin: true)
```

### 5. Configure SSL

```bash
# Add your domain
dokku domains:add your-app-name yourdomain.com

# Enable Let's Encrypt
dokku plugin:install https://github.com/dokku/dokku-letsencrypt.git
dokku letsencrypt:set your-app-name email admin@yourdomain.com
dokku letsencrypt:enable your-app-name
```

## Troubleshooting

### Real-time updates not working?
- Check worker is running: `dokku ps:scale your-app-name`
- Worker should be set to 1, not 0
- Check logs: `dokku logs your-app-name -t`

### SSL certificates not working?
- Ensure `DOKKU_LETSENCRYPT_EMAIL` is set
- Domain must be publicly accessible
- Check logs: `dokku letsencrypt:logs your-app-name`

### Database connection errors?
- Ensure tables are created:
  ```bash
  dokku run your-app-name rails runner "load Rails.root.join('db', 'queue_schema.rb')"
  dokku run your-app-name rails runner "load Rails.root.join('db', 'cable_schema.rb')"
  ```

### Background jobs not processing?
- Scale worker to 1: `dokku ps:scale your-app-name worker=1`
- Check SolidQueue is running: `dokku logs your-app-name | grep -i solid`

## Environment Variables

See `.env.example` for all available configuration options.

Key variables:
- `APP_HOST` - Your production domain (required for ActionCable)
- `DOKKU_LETSENCRYPT_EMAIL` - Email for SSL certificates
- `DATABASE_URL` - Set automatically by Dokku
- `SECRET_KEY_BASE` - Rails secret key (auto-generated)

## License

MIT