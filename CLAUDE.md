# CLAUDE.md - AI Assistant Development Guide

## Project Overview

**Vantage-Dokku** is a Rails 8 web application for managing Dokku PaaS deployments at scale. It provides a dashboard for operators to manage multiple Dokku servers, deploy applications, configure databases, manage SSL certificates, and monitor application health without requiring direct SSH access.

**Core Purpose:** Simplify Dokku server management through a web interface with real-time updates, automated deployments, security scanning, and comprehensive monitoring.

---

## Critical Architecture Patterns

### 1. SSH Connection Management

**Location:** `/app/services/ssh_connection_service.rb` (2,831 lines)

This is the **most critical and complex component** of the entire application. All Dokku operations go through SSH connections to remote servers.

**Key Characteristics:**
- Multiple timeout constants for different operation types:
  ```ruby
  CONNECTION_TIMEOUT = 10      # Initial connection
  COMMAND_TIMEOUT = 30         # Standard commands
  UPDATE_TIMEOUT = 600         # Server updates (10 min)
  INSTALL_TIMEOUT = 900        # Dokku installation (15 min)
  DOMAIN_TIMEOUT = 600         # Domain/SSL operations (10 min)
  ENV_TIMEOUT = 180            # Environment variables (3 min)
  ```

- Always returns a hash with consistent structure:
  ```ruby
  {
    success: boolean,
    error: string or nil,
    output: string,
    # ... other operation-specific keys
  }
  ```

- Updates `server.last_connected_at` on successful connection

**CRITICAL: SSH Error Handling**

**ALWAYS handle these Net::SSH exceptions:**
```ruby
rescue Net::SSH::AuthenticationFailed => e
  result[:error] = "Authentication failed. Please check your SSH key or password."
rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
  result[:error] = "Connection timeout. Server may be unreachable."
rescue Errno::ECONNREFUSED => e
  result[:error] = "Connection refused. Check if SSH service is running on port #{port}."
rescue Errno::EHOSTUNREACH => e
  result[:error] = "Host unreachable. Check the IP address and network connectivity."
rescue StandardError => e
  result[:error] = "Operation failed: #{e.message}"
end
```

**Every method in SshConnectionService follows this pattern.** If you add new SSH operations, you MUST include these rescue clauses.

---

### 2. Real-Time Updates (ActionCable)

**Locations:** `/app/channels/*.rb` (11 channels)

ActionCable provides live progress updates for long-running operations.

**Channel Naming Convention:**
- `{Operation}Channel` (e.g., `DeploymentLogsChannel`, `CommandExecutionChannel`)

**Standard Broadcasting Pattern:**
```ruby
# 1. Update model status
deployment.update!(status: 'deploying')

# 2. Broadcast start
ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", {
  type: 'started',
  message: 'Starting deployment...'
})

# 3. Stream progress updates
output.each_line do |line|
  ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", {
    type: 'data',
    message: sanitize_utf8(line)
  })
end

# 4. Broadcast completion
ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", {
  type: 'completed',
  success: true
})
```

**CRITICAL: Always sanitize UTF-8 before broadcasting SSH output** (see UTF-8 section below).

**Production Configuration:**
- Uses **SolidCable** (database-backed ActionCable)
- Configured in `config/cable.yml`
- Worker process MUST be running (`worker:` in Procfile)

---

### 3. Background Job Architecture

**Location:** `/app/jobs/*.rb` (18 background jobs)

Uses **SolidQueue** (Rails 8) - NOT Sidekiq. All jobs are database-backed.

**Job Naming Convention:**
- `{Operation}Job` (e.g., `DeploymentJob`, `CreateDokkuAppJob`)

**Standard Job Pattern:**
```ruby
class DeploymentJob < ApplicationJob
  queue_as :default

  def perform(deployment)
    # 1. Update status
    deployment.update!(deployment_status: 'deploying')

    # 2. Broadcast to ActionCable
    ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", {
      type: 'started'
    })

    # 3. Perform work (usually via service object)
    service = DeploymentService.new(deployment)
    result = service.deploy_from_repository

    # 4. Update final status
    deployment.update!(
      deployment_status: result[:success] ? 'deployed' : 'failed'
    )

    # 5. Broadcast completion
    ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", {
      type: 'completed',
      success: result[:success]
    })
  end
end
```

**Important:**
- Jobs run in background worker process
- Worker must be scaled in production: `dokku ps:scale app-name worker=1`
- Jobs persist in database (can query with `SolidQueue::Job.all`)
- Failed jobs: `SolidQueue::FailedExecution.all`

**Development vs Production:**
```ruby
if Rails.env.development?
  CreateDokkuAppJob.perform_now(deployment)  # Synchronous
else
  CreateDokkuAppJob.perform_later(deployment)  # Asynchronous
end
```

---

### 4. Service Objects Pattern

**Location:** `/app/services/*.rb`

Service objects encapsulate complex business logic.

**Characteristics:**
- Initialized with primary model: `service = SshConnectionService.new(server)`
- Return hash with `{ success:, error:, ... }` structure
- Extract business logic from controllers
- Make testing easier (can mock services)

**Example Services:**
- `SshConnectionService` - SSH operations and Dokku commands (2,831 lines)
- `DeploymentService` - Deployment workflow (480 lines)
- `ApplicationHealthService` - Health monitoring
- `SslVerificationService` - SSL certificate validation
- `GitHubService` - GitHub API integration

**When to Use Services vs Jobs:**
- **Service:** Encapsulates business logic, can be synchronous
- **Job:** Runs asynchronously in background, often calls services

---

### 5. UUID Routing Pattern

**CRITICAL SECURITY PATTERN - NEVER use database IDs in URLs**

**Why:** Database IDs are sequential and predictable. UUIDs prevent enumeration attacks and information leakage.

**Implementation Pattern:**

**In Models:**
```ruby
class Server < ApplicationRecord
  validates :uuid, presence: true, uniqueness: true
  before_validation :generate_uuid, on: :create

  def to_param
    uuid  # Rails uses this for URL generation
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
```

**In Routes:**
```ruby
resources :servers, param: :uuid do
  member do
    post :test_connection
  end
end

resources :deployments, param: :uuid do
  member do
    post :deploy
    get :logs
  end
end
```

**In Controllers:**
```ruby
# ✅ CORRECT
def show
  @server = Server.find_by!(uuid: params[:uuid])
end

# ❌ WRONG - Never do this!
def show
  @server = Server.find(params[:id])  # Exposes database IDs!
end
```

**Result:**
- ✅ `/servers/550e8400-e29b-41d4-a716-446655440000`
- ❌ `/servers/1` (predictable, enumerableble, reveals database state)

**Models using UUIDs:**
- `Server`
- `Deployment`

---

## Data Model Overview

### Core Models and Relationships

```
User (Devise + Rolify)
  ├─ has_many :servers
  │   ├─ has_many :deployments
  │   │   ├─ has_one :database_configuration
  │   │   ├─ has_many :domains
  │   │   ├─ has_many :environment_variables
  │   │   ├─ has_many :port_mappings
  │   │   ├─ has_many :application_healths
  │   │   ├─ has_many :deployment_attempts
  │   │   ├─ has_many :vulnerability_scans
  │   │   └─ has_and_belongs_to_many :ssh_keys
  │   ├─ has_many :firewall_rules
  │   ├─ has_one :vulnerability_scan_config
  │   └─ has_many :vulnerability_scans
  ├─ has_many :ssh_keys
  ├─ has_many :linked_accounts
  └─ has_many :activity_logs
```

### Key Model Details

#### Server
```ruby
# File: app/models/server.rb
encrypts :password, deterministic: false  # Active Record Encryption
validates :uuid, presence: true, uniqueness: true
validates :ip, format: { with: /\A(?:[0-9]{1,3}\.){3}[0-9]{1,3}\z/ }
validates :port, numericality: { greater_than: 0, less_than_or_equal_to: 65535 }
validates :name, uniqueness: { scope: :user_id }
validates :connection_status, inclusion: { in: %w[unknown connected failed] }

# SSH key management
def ssh_key_paths
  # Priority: ENV variable > AppSetting database values
end

# Temporary key files created with 0600 permissions
```

#### Deployment
```ruby
# File: app/models/deployment.rb
validates :uuid, presence: true, uniqueness: true
validates :dokku_app_name, presence: true, uniqueness: true
validates :dokku_app_name, format: { with: /\A[a-z0-9-]+\z/ }
validates :deployment_method, inclusion: { in: %w[manual github_repo public_repo] }
validates :deployment_status, inclusion: { in: %w[pending deploying deployed failed] }

# Auto-generates random names: "brave-butterfly-kingdom"
before_validation :generate_dokku_app_name, on: :create

# Word lists for name generation
ADJECTIVES = %w[ancient brave calm clever ...]
NOUNS = %w[butterfly kingdom mountain river ...]

# After creation, automatically creates Dokku app
after_create :create_dokku_app_async
```

#### DeploymentAttempt
**CRITICAL PATTERN:** Every deployment creates a DeploymentAttempt record.

```ruby
# Never lose deployment history
belongs_to :deployment
validates :attempt_number, presence: true

# Fields: status, started_at, completed_at, logs, error_message
# Status: pending, running, success, failed
```

**Why:** Provides complete audit trail of all deployment attempts.

---

## Controller Patterns

### ActivityTrackable Concern

**Location:** `/app/controllers/concerns/activity_trackable.rb`

**Purpose:** Logs all user actions for audit trails.

**Usage:**
```ruby
class ServersController < ApplicationController
  include ActivityTrackable

  def create
    @server = current_user.servers.build(server_params)
    if @server.save
      log_activity("Created server", details: "Server: #{@server.name}")
      redirect_to @server
    end
  end

  def destroy
    @server.destroy
    log_activity("Deleted server", details: "Server: #{@server.name}")
    redirect_to servers_path
  end
end
```

**What Gets Logged:**
- User ID
- Action description
- IP address
- User agent
- Controller/action names
- Filtered request parameters (sensitive data removed)

**Sensitive Parameters Filtered:**
- `:password`
- `:password_confirmation`
- `:current_password`
- `:smtp_password`

### Toastable Concern

**Location:** `/app/controllers/concerns/toastable.rb`

**Purpose:** Unified notification system (replaces Rails flash messages).

**Usage:**
```ruby
class DeploymentsController < ApplicationController
  include Toastable

  def deploy
    if service.deploy
      show_toast(:success, "Deployment started successfully")
    else
      show_toast(:error, "Deployment failed: #{service.error}")
    end
  end
end
```

### Authorization (Pundit)

**Location:** `/app/policies/*.rb`

**Policies exist for:**
- `ServerPolicy`
- `DeploymentPolicy`
- `SshKeyPolicy`
- `LinkedAccountPolicy`
- `VulnerabilityScanPolicy`

**Pattern:**
```ruby
class DeploymentsController < ApplicationController
  def show
    @deployment = Deployment.find_by!(uuid: params[:uuid])
    authorize @deployment  # Calls DeploymentPolicy#show?
  end

  def destroy
    @deployment = Deployment.find_by!(uuid: params[:uuid])
    authorize @deployment  # Calls DeploymentPolicy#destroy?
    @deployment.destroy
  end
end
```

**Scope Pattern:**
```ruby
# Users see only their own resources
def index
  @servers = policy_scope(Server)  # Returns current_user.servers
end

# Admins see all resources
# Policy handles this based on user roles
```

---

## Critical Coding Conventions

### 1. UTF-8 Encoding for SSH Output

**CRITICAL:** SSH output can contain invalid UTF-8 bytes that will crash ActionCable broadcasts.

**Always sanitize before storing or broadcasting:**

```ruby
def sanitize_utf8(text)
  return '' if text.nil?

  # Force UTF-8 encoding
  clean_text = text.force_encoding('UTF-8')

  # Replace invalid bytes if encoding is invalid
  unless clean_text.valid_encoding?
    clean_text = text.encode('UTF-8', 'UTF-8',
      invalid: :replace,   # Replace invalid bytes
      undef: :replace,     # Replace undefined characters
      replace: '?')        # Replacement character
  end

  clean_text
end
```

**Why:** Docker build outputs, Linux kernel messages, and non-English error messages can contain invalid UTF-8. Without sanitization, ActionCable broadcasts will fail silently.

**Where to use:**
- Before broadcasting to ActionCable channels
- Before saving SSH output to database
- Before rendering SSH output in views

---

### 2. DeploymentAttempt Tracking

**ALWAYS create a DeploymentAttempt record for every deployment:**

```ruby
class DeploymentService
  def initialize(deployment, deployment_attempt = nil)
    @deployment = deployment
    @deployment_attempt = deployment_attempt || create_deployment_attempt
  end

  def deploy_from_repository
    # Mark attempt as started
    @deployment_attempt.update!(
      status: 'running',
      started_at: Time.current
    )

    # Perform deployment...

    # Mark attempt as complete
    @deployment_attempt.update!(
      status: result[:success] ? 'success' : 'failed',
      completed_at: Time.current,
      logs: @logs.join("\n"),
      error_message: result[:error]
    )
  end

  private

  def create_deployment_attempt
    DeploymentAttempt.create!(
      deployment: @deployment,
      attempt_number: @deployment.deployment_attempts.count + 1,
      status: 'pending'
    )
  end
end
```

**Why:** Complete audit trail of every deployment attempt, including logs and error messages.

---

### 3. Timeout Management

**Use appropriate timeouts for different operations:**

```ruby
# Quick operations (info queries)
Timeout::timeout(COMMAND_TIMEOUT) do  # 30 seconds
  ssh.exec!("dokku apps:list")
end

# Medium operations (environment variables)
Timeout::timeout(ENV_TIMEOUT) do  # 3 minutes
  ssh.exec!("dokku config:set myapp KEY=value")
end

# Long operations (deployments, updates)
Timeout::timeout(UPDATE_TIMEOUT) do  # 10 minutes
  ssh.exec!("apt-get update && apt-get upgrade -y")
end

# Very long operations (installations)
Timeout::timeout(INSTALL_TIMEOUT) do  # 15 minutes
  ssh.exec!(dokku_installation_script)
end
```

**Never:**
- Use same timeout for all operations
- Use timeout without rescue clause
- Use infinite timeouts (no timeout at all)

---

### 4. AppSetting Pattern

**Configuration stored in database (dynamic settings):**

```ruby
# Get setting
dokku_key_path = AppSetting.get('dokku_ssh_key_path')

# Set setting
AppSetting.set('dokku_ssh_key_path',
  '/var/dokku/.ssh/id_ed25519',
  description: 'Path to Dokku SSH private key',
  setting_type: 'string'
)

# Check existence
if AppSetting.exists?('smtp_enabled')
  # ...
end
```

**Setting Types:**
- `string` - Text values
- `boolean` - true/false
- `integer` - Numeric values

**Common Settings:**
- `dokku_ssh_key_path` - SSH key file path
- `dokku_ssh_private_key` - SSH private key content
- `require_email_confirmation` - Email confirmation toggle
- `maintenance_mode` - Prevent non-admin access

---

## Configuration Management

### Environment Variables

**Required:**
- `APP_HOST` - Application hostname (e.g., `vantage.example.com`)
- `SECRET_KEY_BASE` - Rails secret (generate with `rails secret`)
- `DATABASE_URL` - PostgreSQL connection string

**Optional:**
- `REDIS_URL` - Redis connection (optional with SolidQueue)
- `GOOGLE_OAUTH_CLIENT_ID` - Google OAuth
- `GOOGLE_OAUTH_CLIENT_SECRET` - Google OAuth secret
- `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD` - Email
- `DOKKU_LETSENCRYPT_EMAIL` - Let's Encrypt notifications

**Multi-Database Configuration (Production):**
```yaml
# config/database.yml
production:
  primary:
    <<: *default
    database: vantage_production
  cache:
    <<: *default
    database: vantage_production
    migrations_paths: db/cache_migrate
  queue:
    <<: *default
    database: vantage_production
    migrations_paths: db/queue_migrate
  cable:
    <<: *default
    database: vantage_production
    migrations_paths: db/cable_migrate
```

All databases use same PostgreSQL instance with different schemas.

---

## Testing Conventions

### Current State
- Uses Rails default testing (Minitest)
- Model tests in `/test/models/`
- Controller tests (limited)
- System tests with Selenium/Chrome

### When Adding Tests

**Model Testing:**
```ruby
# test/models/server_test.rb
require "test_helper"

class ServerTest < ActiveSupport::TestCase
  test "should generate UUID on creation" do
    server = Server.new(name: "Test", ip: "1.2.3.4", ...)
    assert_nil server.uuid
    server.save!
    assert_not_nil server.uuid
  end

  test "should use UUID for to_param" do
    server = servers(:one)
    assert_equal server.uuid, server.to_param
  end
end
```

**Job Testing (Mock SSH):**
```ruby
# Don't make actual SSH connections in tests
class DeploymentJobTest < ActiveSupport::TestCase
  test "should update deployment status" do
    deployment = deployments(:one)

    # Mock the service
    SshConnectionService.any_instance.stubs(:deploy).returns({
      success: true,
      output: "Deployed successfully"
    })

    DeploymentJob.perform_now(deployment)

    assert_equal 'deployed', deployment.reload.deployment_status
  end
end
```

---

## What to AVOID

### ❌ 1. Database IDs in URLs

```ruby
# ❌ WRONG
resources :servers  # Uses :id
@server = Server.find(params[:id])

# ✅ CORRECT
resources :servers, param: :uuid
@server = Server.find_by!(uuid: params[:uuid])
```

### ❌ 2. Skipping SSH Error Handling

```ruby
# ❌ WRONG - Will crash on connection errors
def test_connection
  Net::SSH.start(host, username, ssh_options) do |ssh|
    ssh.exec!("echo 'test'")
  end
end

# ✅ CORRECT
def test_connection
  result = { success: false, error: nil }

  begin
    Net::SSH.start(host, username, ssh_options) do |ssh|
      ssh.exec!("echo 'test'")
      result[:success] = true
    end
  rescue Net::SSH::AuthenticationFailed => e
    result[:error] = "Authentication failed"
  rescue Net::SSH::ConnectionTimeout => e
    result[:error] = "Connection timeout"
  # ... other rescue clauses
  end

  result
end
```

### ❌ 3. Blocking Web Requests

```ruby
# ❌ WRONG - Blocks user's browser for minutes
def deploy
  service = DeploymentService.new(@deployment)
  service.deploy_from_repository  # Takes 5-10 minutes!
  redirect_to @deployment
end

# ✅ CORRECT
def deploy
  DeploymentJob.perform_later(@deployment)
  redirect_to @deployment, notice: "Deployment started"
end
```

### ❌ 4. Forgetting UTF-8 Sanitization

```ruby
# ❌ WRONG - Will crash ActionCable
ssh_output = ssh.exec!("dokku apps")
ActionCable.server.broadcast("channel", { data: ssh_output })

# ✅ CORRECT
ssh_output = ssh.exec!("dokku apps")
clean_output = sanitize_utf8(ssh_output)
ActionCable.server.broadcast("channel", { data: clean_output })
```

### ❌ 5. Modifying SshConnectionService Without Testing

SshConnectionService is 2,831 lines and affects **every feature**. Changes here can break:
- Deployments
- Server updates
- Firewall rules
- Vulnerability scanning
- Domain/SSL management
- Database configuration
- Environment variables

**ALWAYS:**
- Test changes thoroughly
- Add error handling
- Maintain consistent return structure: `{ success:, error:, ... }`

---

## Security Considerations

### 1. Encrypted Attributes

```ruby
# app/models/server.rb
encrypts :password, deterministic: false

# app/models/linked_account.rb
encrypts :access_token, deterministic: false
```

**How it works:**
- Rails 7+ built-in encryption
- Transparent encryption/decryption
- Keys in `config/credentials.yml.enc` or ENV
- Cannot query encrypted fields directly

**Generate encryption keys:**
```bash
rails db:encryption:init
```

### 2. SSH Key Security

**File permissions:**
```ruby
File.chmod(0600, key_path)  # Readable only by owner
```

**Temporary key files:**
- Created on-demand
- Stored in secure directory
- Deleted after use (or on next request)

**Never:**
- Commit SSH keys to git
- Log SSH private keys
- Display keys in UI (except public keys)

### 3. Activity Logging

**Every administrative action is logged:**
- Who performed it (User ID)
- When (timestamp)
- What (action description)
- Where from (IP address)
- How (user agent)
- With what (filtered parameters)

**Sensitive data is filtered:**
```ruby
def filter_sensitive_params(params_hash)
  params_hash.except(:password, :password_confirmation,
                     :current_password, :smtp_password)
end
```

### 4. Authorization (Pundit)

**Every controller action checks authorization:**
```ruby
def show
  @deployment = Deployment.find_by!(uuid: params[:uuid])
  authorize @deployment  # Raises Pundit::NotAuthorizedError if unauthorized
end
```

**Scope queries to current user:**
```ruby
# Regular users see only their own resources
policy_scope(Server)  # => current_user.servers

# Admins see all resources (policy handles this)
```

---

## Common Development Tasks

### Adding a New Background Job

1. **Create job file:**
```ruby
# app/jobs/my_operation_job.rb
class MyOperationJob < ApplicationJob
  queue_as :default

  def perform(model)
    # Update status
    model.update!(status: 'processing')

    # Broadcast start
    ActionCable.server.broadcast("my_operation_#{model.uuid}", {
      type: 'started'
    })

    # Perform work
    result = MyService.new(model).perform

    # Update final status
    model.update!(status: result[:success] ? 'completed' : 'failed')

    # Broadcast completion
    ActionCable.server.broadcast("my_operation_#{model.uuid}", {
      type: 'completed',
      success: result[:success]
    })
  end
end
```

2. **Create corresponding ActionCable channel:**
```ruby
# app/channels/my_operation_channel.rb
class MyOperationChannel < ApplicationCable::Channel
  def subscribed
    model = Model.find_by(uuid: params[:uuid])
    stream_from "my_operation_#{model.uuid}"
  end
end
```

3. **Call job from controller:**
```ruby
def start_operation
  @model = Model.find_by!(uuid: params[:uuid])
  authorize @model
  MyOperationJob.perform_later(@model)
  redirect_to @model, notice: "Operation started"
end
```

### Adding a New Model

1. **Generate migration with UUID:**
```bash
rails g model MyModel name:string uuid:string:uniq
```

2. **Add UUID pattern to model:**
```ruby
class MyModel < ApplicationRecord
  validates :uuid, presence: true, uniqueness: true
  before_validation :generate_uuid, on: :create

  def to_param
    uuid
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
```

3. **Use UUID in routes:**
```ruby
resources :my_models, param: :uuid
```

4. **Find by UUID in controller:**
```ruby
def show
  @my_model = MyModel.find_by!(uuid: params[:uuid])
end
```

### Adding SSH Operations

1. **Add method to SshConnectionService:**
```ruby
def my_ssh_operation
  result = { success: false, error: nil, output: '' }

  begin
    Timeout::timeout(COMMAND_TIMEOUT) do
      Net::SSH.start(@connection_details[:host],
                     @connection_details[:username],
                     ssh_options) do |ssh|
        result[:output] = ssh.exec!("my command")
        result[:success] = true
        @server.update!(last_connected_at: Time.current)
      end
    end
  rescue Net::SSH::AuthenticationFailed => e
    result[:error] = "Authentication failed"
  rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
    result[:error] = "Connection timeout"
  rescue Errno::ECONNREFUSED => e
    result[:error] = "Connection refused"
  rescue Errno::EHOSTUNREACH => e
    result[:error] = "Host unreachable"
  rescue StandardError => e
    result[:error] = "Operation failed: #{e.message}"
  end

  result
end
```

2. **Use appropriate timeout constant**
3. **Handle all SSH exceptions**
4. **Update last_connected_at on success**
5. **Return consistent hash structure**

---

## File Locations Reference

### Critical Files
- **SSH Integration:** `/app/services/ssh_connection_service.rb` (2,831 lines)
- **Deployment Logic:** `/app/services/deployment_service.rb` (480 lines)
- **Server Model:** `/app/models/server.rb`
- **Deployment Model:** `/app/models/deployment.rb`
- **Activity Logging:** `/app/controllers/concerns/activity_trackable.rb`
- **Toast Notifications:** `/app/controllers/concerns/toastable.rb`

### Configuration
- **Routes:** `/config/routes.rb`
- **Database:** `/config/database.yml`
- **ActionCable:** `/config/cable.yml`
- **SolidQueue:** `/config/queue.yml`
- **Devise:** `/config/initializers/devise.rb`
- **OAuth:** `/config/initializers/01_oauth_config.rb`
- **SMTP:** `/config/initializers/smtp_configuration.rb`

### Background Jobs
- **All Jobs:** `/app/jobs/*.rb` (18 jobs)
- **Most Important:**
  - `DeploymentJob`
  - `CreateDokkuAppJob`
  - `ApplicationHealthCheckJob`
  - `VulnerabilityScannerJob`

### ActionCable Channels
- **All Channels:** `/app/channels/*.rb` (11 channels)
- **Most Important:**
  - `DeploymentLogsChannel`
  - `CommandExecutionChannel`
  - `ServerLogsChannel`
  - `DatabaseConfigurationChannel`

### Policies
- **All Policies:** `/app/policies/*.rb`
- `ServerPolicy`, `DeploymentPolicy`, `SshKeyPolicy`

---

## Debugging Tips

### ActionCable Issues

**Symptom:** Real-time updates not working

**Check:**
1. Worker process running?
   ```bash
   # Check Procfile has worker definition
   ps aux | grep solid_queue
   ```

2. APP_HOST matches your domain?
   ```ruby
   # config/environments/production.rb
   config.action_cable.url = "wss://#{ENV['APP_HOST']}/cable"
   ```

3. Browser WebSocket connection?
   - Open browser dev tools → Network → WS tab
   - Look for `/cable` connection
   - Check for errors

4. ActionCable logs?
   ```bash
   tail -f log/production.log | grep ActionCable
   ```

### SSH Connection Issues

**Symptom:** "Authentication failed"

**Check:**
1. SSH key permissions:
   ```bash
   ls -l ~/.ssh/id_ed25519  # Should be -rw------- (0600)
   ```

2. Server username correct?
3. Password provided if no SSH key?
4. Server firewall allows SSH port?

**Test manually:**
```bash
ssh -i /path/to/key user@server-ip -p port
```

### Background Job Issues

**Symptom:** Jobs not running

**Check:**
1. Worker process running?
   ```ruby
   SolidQueue::Process.all  # Should show active processes
   ```

2. Jobs in queue?
   ```ruby
   SolidQueue::Job.all
   SolidQueue::Job.pending.count
   ```

3. Failed jobs?
   ```ruby
   SolidQueue::FailedExecution.all
   SolidQueue::FailedExecution.last&.error
   ```

4. Worker logs?
   ```bash
   tail -f log/production.log | grep SolidQueue
   ```

---

## Additional Documentation

For more detailed information, see:
- `/docs/ARCHITECTURE.md` - System architecture and design
- `/docs/CONVENTIONS.md` - Code style and patterns
- `/docs/features/ssh-integration.md` - SSH implementation details
- `/docs/features/real-time-updates.md` - ActionCable patterns
- `/docs/features/deployment-system.md` - Deployment workflow
- `/docs/GETTING_STARTED.md` - Developer onboarding guide
- `/docs/development/debugging.md` - Troubleshooting guide

---

**Remember:** This project was built heavily with Claude Code. This CLAUDE.md file helps maintain consistency and prevents common mistakes across sessions. Update this file when new patterns emerge or important decisions are made.
