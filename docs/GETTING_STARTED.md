# Getting Started

Welcome to Vantage-Dokku! This guide will help you set up your local development environment and get started contributing to the project.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Initial Setup](#initial-setup)
3. [Database Setup](#database-setup)
4. [Environment Configuration](#environment-configuration)
5. [Running the Application](#running-the-application)
6. [Creating Your First Server](#creating-your-first-server)
7. [Creating Your First Deployment](#creating-your-first-deployment)
8. [Common Development Workflows](#common-development-workflows)
9. [Troubleshooting Setup Issues](#troubleshooting-setup-issues)

---

## Prerequisites

### Required Software

**Ruby 3.4.5**
```bash
# Check Ruby version
ruby -v
# => ruby 3.4.5

# Install with rbenv (recommended)
rbenv install 3.4.5
rbenv global 3.4.5

# Or with rvm
rvm install 3.4.5
rvm use 3.4.5
```

**PostgreSQL 12+**
```bash
# macOS (Homebrew)
brew install postgresql@15
brew services start postgresql@15

# Ubuntu/Debian
sudo apt-get install postgresql postgresql-contrib
sudo systemctl start postgresql

# Fedora/RHEL
sudo dnf install postgresql-server postgresql-contrib
sudo postgresql-setup --initdb
sudo systemctl start postgresql

# Verify installation
psql --version
# => psql (PostgreSQL) 15.x
```

**Bundler**
```bash
gem install bundler
bundler -v
# => Bundler version 2.5.x
```

### Optional Software

**Redis (optional)**
- Not required for development (SolidQueue/SolidCable use PostgreSQL)
- Useful for testing Redis-based features

```bash
# macOS
brew install redis
brew services start redis

# Ubuntu/Debian
sudo apt-get install redis-server
sudo systemctl start redis

# Verify
redis-cli ping
# => PONG
```

**Node.js (optional)**
- Not required (project uses Importmap, not webpack/esbuild)
- Only needed if you add npm dependencies

### Development Tools

**Recommended:**
- **Git** - Version control
- **VS Code** or **RubyMine** - Code editor
- **Postico/pgAdmin** - PostgreSQL GUI (optional)
- **curl** or **HTTPie** - API testing

---

## Initial Setup

### 1. Clone Repository

```bash
git clone https://github.com/yourusername/vantage-dokku.git
cd vantage-dokku
```

### 2. Install Dependencies

```bash
# Install Ruby gems
bundle install

# If bundle install fails with permission errors:
bundle install --path vendor/bundle

# Verify installation
bundle check
# => The Gemfile's dependencies are satisfied
```

**Common issues:**
- `pg` gem fails to install → Install PostgreSQL development headers
  ```bash
  # Ubuntu/Debian
  sudo apt-get install libpq-dev

  # Fedora/RHEL
  sudo dnf install postgresql-devel

  # macOS
  brew install postgresql
  ```

- `ed25519` gem fails → Install libsodium
  ```bash
  # macOS
  brew install libsodium

  # Ubuntu/Debian
  sudo apt-get install libsodium-dev
  ```

---

## Database Setup

### 1. Create PostgreSQL User

```bash
# Create user for development
sudo -u postgres createuser -s vantage_user

# Or with psql
sudo -u postgres psql
postgres=# CREATE USER vantage_user WITH SUPERUSER PASSWORD 'password';
postgres=# \q
```

### 2. Configure Database Connection

**Option A: Use default settings**

```bash
# config/database.yml expects:
# - Username: postgres (or your system user)
# - Password: (blank)
# - Host: localhost
```

**Option B: Custom settings in .env**

```bash
cp .env.example .env

# Edit .env
DATABASE_URL=postgresql://vantage_user:password@localhost/vantage_dokku_development
```

### 3. Create Databases

```bash
# Create all databases (development, test)
rails db:create

# Expected output:
# Created database 'vantage_dokku_development'
# Created database 'vantage_dokku_test'
```

### 4. Run Migrations

```bash
# Run migrations for primary database
rails db:migrate

# Load queue schema (SolidQueue)
rails runner "load Rails.root.join('db', 'queue_schema.rb')"

# Load cable schema (SolidCable)
rails runner "load Rails.root.join('db', 'cable_schema.rb')"

# Load cache schema (SolidCache)
rails runner "load Rails.root.join('db', 'cache_schema.rb')"

# Verify tables created
rails db:schema:dump
# => db/schema.rb updated
```

### 5. Seed Database (Optional)

```bash
# Load sample data
rails db:seed

# Creates:
# - Demo user (admin@example.com / password)
# - Sample server
# - Sample deployment
```

**Note:** Seed file may not be fully configured. Check `db/seeds.rb` before running.

---

## Environment Configuration

### 1. Create .env File

```bash
cp .env.example .env
```

### 2. Configure Essential Variables

**Edit `.env`:**

```bash
# Rails Configuration
RAILS_ENV=development
SECRET_KEY_BASE=$(rails secret)  # Generate with: rails secret

# Database (if using custom settings)
DATABASE_URL=postgresql://vantage_user:password@localhost/vantage_dokku_development

# Application Host (for ActionCable)
APP_HOST=localhost:3000

# Disable SSL in development
FORCE_SSL=false

# Dokku Let's Encrypt Email (used when setting up SSL)
DOKKU_LETSENCRYPT_EMAIL=your-email@example.com
```

### 3. Configure Optional Features

**Google OAuth (optional):**
1. Create OAuth credentials at [Google Cloud Console](https://console.cloud.google.com/)
2. Add authorized redirect URI: `http://localhost:3000/users/auth/google_oauth2/callback`
3. Add credentials to `.env`:
   ```bash
   GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
   GOOGLE_CLIENT_SECRET=your-client-secret
   ```

**SMTP (optional - for email testing):**
```bash
SMTP_ADDRESS=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your-email@gmail.com
SMTP_PASSWORD=your-app-password
SMTP_FROM_EMAIL=noreply@yourdomain.com
```

**Tip:** Use [Mailpit](https://github.com/axllent/mailpit) or Letter Opener for local email testing instead of real SMTP.

---

## Running the Application

### 1. Start Rails Server

**Option A: Using bin/dev (recommended)**

```bash
# Starts both web and worker processes
bin/dev

# Output:
# web: rails server
# worker: bundle exec rake solid_queue:start
```

**Procfile.dev contents:**
```yaml
web: bin/rails server -p 3000
worker: bundle exec rake solid_queue:start
```

**Option B: Manual start (for debugging)**

```bash
# Terminal 1: Web server
rails server

# Terminal 2: Background worker
bundle exec rake solid_queue:start
```

### 2. Verify Application Running

```bash
# Check web server
curl http://localhost:3000/up
# => OK

# Or visit in browser:
open http://localhost:3000
```

### 3. Create Admin User

```bash
# Open Rails console
rails console

# Create admin user
User.create!(
  email: 'admin@example.com',
  password: 'password123',
  password_confirmation: 'password123',
  first_name: 'Admin',
  last_name: 'User'
)

# Assign admin role
user = User.find_by(email: 'admin@example.com')
user.add_role(:admin)

# Confirm user (skip email confirmation)
user.confirm  # If using Devise confirmable

# Exit console
exit
```

### 4. Log In

1. Visit `http://localhost:3000`
2. Click "Sign In"
3. Enter credentials:
   - Email: `admin@example.com`
   - Password: `password123`
4. You're in!

---

## Creating Your First Server

### Prerequisites

You need a **real Dokku server** to test deployments. Options:

1. **Local Dokku (for testing):**
   - Run Dokku in a VM (VirtualBox/VMware)
   - Use Vagrant with Dokku box
   - [Dokku Documentation](https://dokku.com/docs/getting-started/installation/)

2. **Cloud Dokku Server:**
   - DigitalOcean droplet with Dokku pre-installed
   - AWS EC2 with manual Dokku installation
   - Any Ubuntu 20.04+ server

**Minimum server requirements:**
- Ubuntu 20.04 or 22.04
- 2GB RAM (4GB recommended)
- 25GB disk space
- SSH access (port 22)

### Step 1: Add Server

1. Navigate to **Servers** → **New Server**
2. Fill in server details:
   - **Name:** `My Test Server`
   - **IP Address:** `your-server-ip`
   - **Username:** `root` or `dokku`
   - **Port:** `22`
   - **Password:** (optional, SSH key preferred)

3. Click **Create Server**

### Step 2: Test Connection

1. On server show page, click **Test Connection**
2. Watch real-time output via ActionCable
3. Should see: "✓ Connection successful"

**If connection fails:**
- Check IP address is correct
- Verify SSH port (usually 22)
- Test manually: `ssh username@ip-address`
- Check firewall allows SSH (port 22)

### Step 3: Install Dokku (if needed)

1. If Dokku not detected, click **Install Dokku**
2. Wait ~15 minutes for installation
3. Real-time logs show progress
4. Installation complete when you see Dokku version

**Manual installation verification:**
```bash
ssh user@server-ip
dokku version
# => dokku version v0.34.0
```

---

## Creating Your First Deployment

### Step 1: Create Deployment

1. Navigate to **Deployments** → **New Deployment**
2. Fill in deployment details:
   - **Name:** `My Test App`
   - **Server:** Select your server
   - **Deployment Method:** Choose one:
     - Manual Git Push
     - GitHub Repository
     - Public Repository

### Step 2A: Manual Git Push

**Local project setup:**
```bash
# In your app directory
git remote add dokku dokku@server-ip:app-name
git push dokku main
```

**Dokku app name:**
- Auto-generated (e.g., `brave-butterfly-kingdom`)
- Shown on deployment page
- Can be customized before deployment

### Step 2B: GitHub Repository

**Requirements:**
1. Link GitHub account (Settings → Linked Accounts)
2. Authorize GitHub OAuth
3. Select repository from dropdown
4. Choose branch (default: `main`)

**Click Deploy:**
- Service clones repository on server
- Pushes to Dokku
- Real-time deployment logs
- Success/failure notification

### Step 2C: Public Repository

**Any public Git repository:**
```
https://github.com/user/repo.git
https://gitlab.com/user/repo.git
https://bitbucket.org/user/repo.git
```

**Enter:**
- Repository URL (HTTPS format)
- Branch name
- Click **Deploy**

### Step 3: Watch Deployment

**Real-time progress:**
1. Deployment logs stream live
2. See buildpack detection
3. See Docker build steps
4. See container creation
5. Final status: Success or Failed

**Typical deployment flow:**
```
[10:30:15] Starting repository deployment
[10:30:16] Repository: https://github.com/user/app.git
[10:30:16] Branch: main
[10:30:17] Cloning repository...
[10:30:20] ✓ Repository cloned successfully
[10:30:21] Pushing to Dokku...
[10:30:22] DEPLOY: -----> Detecting buildpack...
[10:30:23] DEPLOY: -----> Ruby app detected
[10:30:45] DEPLOY: -----> Building image
[10:32:10] DEPLOY: =====> Application deployed
[10:32:11] ✓ Git push completed
[10:32:12] Verifying deployment...
[10:32:13] ✓ App is running on Dokku
[10:32:13] ✓ Deployment completed successfully!
```

### Step 4: Verify Deployment

**Check deployment:**
1. Deployment shows status badge: "Deployed"
2. Click app URL (e.g., `http://app.server-ip.nip.io`)
3. App should load in browser

**If deployment failed:**
- Check deployment logs for errors
- Common issues:
  - Missing Procfile or Dockerfile
  - Build errors
  - Port binding issues
  - Environment variables missing

---

## Common Development Workflows

### Daily Development

```bash
# Pull latest changes
git pull origin main

# Install new dependencies (if Gemfile changed)
bundle install

# Run new migrations (if any)
rails db:migrate

# Start development server
bin/dev

# Open in browser
open http://localhost:3000
```

### Running Tests

```bash
# Run all tests
rails test

# Run specific test file
rails test test/models/server_test.rb

# Run specific test
rails test test/models/server_test.rb:10

# Run system tests (with browser)
rails test:system
```

### Database Operations

```bash
# Reset database (WARNING: destroys data!)
rails db:drop db:create db:migrate

# Rollback last migration
rails db:rollback

# Rollback multiple migrations
rails db:rollback STEP=3

# Redo last migration
rails db:migrate:redo

# Check migration status
rails db:migrate:status
```

### Rails Console

```bash
# Open Rails console
rails console
# or
rails c

# Test queries
User.all
Server.count
Deployment.where(deployment_status: 'deployed')

# Test services
server = Server.first
service = SshConnectionService.new(server)
result = service.test_connection
puts result[:success]

# Exit
exit
```

### Background Jobs

```bash
# Check job queue
rails console
SolidQueue::Job.all
SolidQueue::Job.pending.count

# Check failed jobs
SolidQueue::FailedExecution.all
SolidQueue::FailedExecution.last.error

# Manually run job
DeploymentJob.perform_now(deployment)
```

### Logs

```bash
# Tail development log
tail -f log/development.log

# Tail with filtering
tail -f log/development.log | grep DeploymentService

# Clear logs
> log/development.log
```

### Code Quality

```bash
# Run RuboCop (linter)
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -a

# Run Brakeman (security scanner)
bundle exec brakeman
```

---

## Troubleshooting Setup Issues

### "Database does not exist"

**Error:**
```
ActiveRecord::NoDatabaseError: FATAL:  database "vantage_dokku_development" does not exist
```

**Solution:**
```bash
rails db:create
rails db:migrate
```

### "PG::ConnectionBad: could not connect to server"

**Error:**
```
PG::ConnectionBad: could not connect to server: Connection refused
```

**Solutions:**
1. **PostgreSQL not running:**
   ```bash
   # macOS
   brew services start postgresql@15

   # Linux
   sudo systemctl start postgresql
   ```

2. **Wrong connection settings:**
   ```bash
   # Check .env or config/database.yml
   # Verify username, password, host, port
   ```

3. **PostgreSQL not listening on localhost:**
   ```bash
   # Edit postgresql.conf
   listen_addresses = 'localhost'

   # Restart PostgreSQL
   ```

### "Gem::LoadError: Specified 'postgresql' for database adapter, but the gem is not loaded"

**Solution:**
```bash
# Install pg gem
bundle install

# If fails, install PostgreSQL dev headers first
# Then retry bundle install
```

### "ActionCable WebSocket not connecting"

**Symptoms:**
- No real-time updates
- Browser console shows WebSocket errors

**Solutions:**
1. **APP_HOST not set:**
   ```bash
   # In .env
   APP_HOST=localhost:3000
   ```

2. **Worker not running:**
   ```bash
   # Start worker process
   bundle exec rake solid_queue:start
   ```

3. **Cable schema not loaded:**
   ```bash
   rails runner "load Rails.root.join('db', 'cable_schema.rb')"
   ```

### "Bundler::GemRequireError: There was an error while trying to load the gem 'ed25519'"

**Solution:**
```bash
# Install libsodium
# macOS
brew install libsodium

# Ubuntu/Debian
sudo apt-get install libsodium-dev

# Retry bundle install
bundle install
```

### "rails: command not found"

**Solution:**
```bash
# Ensure Ruby is installed
ruby -v

# Install Rails globally (optional)
gem install rails

# Or use bundle exec
bundle exec rails server
```

### Background jobs not processing

**Symptoms:**
- Deployments stuck in "pending"
- No job processing

**Solutions:**
1. **Worker not running:**
   ```bash
   # Check processes
   ps aux | grep solid_queue

   # Start worker
   bundle exec rake solid_queue:start
   ```

2. **Queue schema not loaded:**
   ```bash
   rails runner "load Rails.root.join('db', 'queue_schema.rb')"
   ```

3. **Check for errors:**
   ```bash
   rails console
   SolidQueue::FailedExecution.all
   ```

---

## Next Steps

Now that you have Vantage-Dokku running locally:

1. **Explore the codebase:**
   - Read `/CLAUDE.md` for AI-specific guidance
   - Read `/docs/ARCHITECTURE.md` for system design
   - Read `/docs/CONVENTIONS.md` for coding patterns

2. **Try features:**
   - Create a server
   - Test connection
   - Deploy an application
   - Configure domains
   - Add SSL certificates
   - Manage environment variables

3. **Understand key components:**
   - Models: `app/models/`
   - Services: `app/services/`
   - Jobs: `app/jobs/`
   - Channels: `app/channels/`

4. **Read feature documentation:**
   - [SSH Integration](/docs/features/ssh-integration.md)
   - [Real-Time Updates](/docs/features/real-time-updates.md)
   - [Deployment System](/docs/features/deployment-system.md)

5. **Start developing:**
   - Pick an issue from GitHub
   - Create a feature branch
   - Write tests
   - Submit a pull request

---

## Getting Help

**Documentation:**
- `/CLAUDE.md` - AI assistant guide
- `/docs/ARCHITECTURE.md` - System design
- `/docs/features/*.md` - Feature-specific docs
- `/docs/development/*.md` - Development guides

**Community:**
- GitHub Issues
- Discussions
- Pull Requests

**External Resources:**
- [Rails Guides](https://guides.rubyonrails.org/)
- [Dokku Documentation](https://dokku.com/docs/)
- [PostgreSQL Documentation](https://www.postgresql.org/docs/)

---

Welcome aboard! Happy coding! 🚀
