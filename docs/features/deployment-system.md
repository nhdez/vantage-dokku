# Deployment System

## Overview

The deployment system orchestrates automated application deployments from Git repositories to Dokku servers. It handles repository cloning, authentication, Docker builds, and deployment verification with real-time progress updates.

**Location:** `/app/services/deployment_service.rb` (480 lines)

**Purpose:** Deploy applications from GitHub (private/public) or public Git repositories to Dokku servers with complete audit trails and real-time feedback.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Deployment Workflow](#deployment-workflow)
3. [DeploymentAttempt Tracking](#deploymentattempt-tracking)
4. [Repository Cloning Strategies](#repository-cloning-strategies)
5. [Git Authentication](#git-authentication)
6. [Dokku App Creation](#dokku-app-creation)
7. [Auto-Name Generation](#auto-name-generation)
8. [Deployment Verification](#deployment-verification)
9. [Real-Time Progress](#real-time-progress)
10. [Error Handling](#error-handling)
11. [Common Deployment Issues](#common-deployment-issues)

---

## Architecture

### Deployment Flow

```
┌─────────────────────────────────────────────────────────┐
│                User Interface                           │
│  Click "Deploy" button                                  │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│           DeploymentsController                         │
│  def deploy                                             │
│    authorize @deployment                                │
│    DeploymentJob.perform_later(@deployment)            │
│    redirect_to @deployment                              │
│  end                                                     │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│           DeploymentJob (Background Job)                │
│  def perform(deployment)                                │
│    service = DeploymentService.new(deployment)         │
│    service.deploy_from_repository                       │
│  end                                                     │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│         DeploymentService (Business Logic)              │
│                                                          │
│  1. Create DeploymentAttempt (audit record)            │
│  2. Connect to server via SSH                           │
│  3. Create Dokku app if doesn't exist                  │
│  4. Clone Git repository                                │
│  5. Setup SSH keys for Dokku                            │
│  6. Push to Dokku (triggers build)                      │
│  7. Verify deployment (check if running)               │
│  8. Update attempt status (success/failed)              │
│  9. Broadcast completion via ActionCable                │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│              Remote Dokku Server                        │
│                                                          │
│  1. Receive git push                                    │
│  2. Detect buildpack or Dockerfile                      │
│  3. Build Docker image                                  │
│  4. Create container(s)                                 │
│  5. Configure nginx proxy                               │
│  6. Start application                                   │
│  7. Report status                                       │
└─────────────────────────────────────────────────────────┘
```

### Components

**Models:**
- `Deployment` - Application to be deployed
- `DeploymentAttempt` - Single deployment execution record
- `Server` - Target Dokku server

**Services:**
- `DeploymentService` - Orchestrates deployment workflow
- `SshConnectionService` - Handles SSH communication

**Jobs:**
- `DeploymentJob` - Async wrapper around DeploymentService

**Channels:**
- `DeploymentLogsChannel` - Real-time deployment logs

---

## Deployment Workflow

### Step-by-Step Process

#### 1. Initialize Deployment

```ruby
class DeploymentService
  def initialize(deployment, deployment_attempt = nil)
    @deployment = deployment
    @server = deployment.server
    @logs = []
    @connection_details = @server.connection_details
    @deployment_attempt = deployment_attempt || create_deployment_attempt
  end
end
```

**Creates:**
- `DeploymentAttempt` record with status: 'pending'
- Incremented attempt_number
- Timestamp for tracking

#### 2. Start Deployment

```ruby
def deploy_from_repository
  # Mark attempt as started
  @deployment_attempt.update!(
    status: 'running',
    started_at: Time.current
  )

  log("Starting repository deployment")
  log("Repository: #{@deployment.repository_url}")
  log("Branch: #{@deployment.repository_branch}")
  log("Target server: #{@server.name} (#{@server.ip})")
  log("Attempt ##{@deployment_attempt.attempt_number}")

  # ... proceed with deployment
end
```

**Updates:**
- Attempt status → 'running'
- Records started_at timestamp
- Logs initial deployment info

#### 3. Create Dokku App

```ruby
def create_dokku_app(ssh)
  app_name = @deployment.dokku_app_name

  # Check if app already exists
  result = execute_command(ssh,
    "dokku apps:list 2>/dev/null | grep '^#{app_name}$' || echo 'NOT_FOUND'"
  )

  if result.include?('NOT_FOUND')
    log("Creating new Dokku app: #{app_name}")
    execute_command(ssh, "dokku apps:create #{app_name}")
    log("✓ Dokku app created successfully")
  else
    log("✓ Dokku app already exists")
  end
end
```

**Idempotent:** Safe to run multiple times, won't fail if app exists

#### 4. Clone Repository

```ruby
def deploy_with_git(ssh)
  app_name = @deployment.dokku_app_name
  repo_url = @deployment.repository_url
  branch = @deployment.repository_branch

  # Create unique directory
  deploy_dir = "/home/dokku/#{app_name}-deploy-#{Time.current.to_i}"

  # Prepare authenticated URL (for private repos)
  authenticated_repo_url = prepare_authenticated_repo_url(repo_url)

  # Clone repository
  log("Cloning #{repo_url} (branch: #{branch})")
  clone_result = execute_command(ssh,
    "cd /home/dokku && git clone -b #{branch} #{authenticated_repo_url} #{deploy_dir}"
  )

  # Handle branch not found
  if clone_result.include?('fatal:') || clone_result.include?('error:')
    log("Branch-specific clone failed, trying alternative approach...")
    execute_command(ssh, "rm -rf #{deploy_dir}")

    # Clone without branch, then checkout
    clone_result = execute_command(ssh,
      "cd /home/dokku && git clone #{authenticated_repo_url} #{deploy_dir}"
    )

    if !clone_result.include?('fatal:')
      # Checkout specific branch
      execute_command(ssh, "cd #{deploy_dir} && git checkout #{branch}")
    end
  end

  log("✓ Repository cloned successfully")
end
```

**Features:**
- Fallback strategy if branch doesn't exist
- Authenticated URLs for private repos
- Unique directory per deployment (timestamp)
- Cleanup in `ensure` block

#### 5. Setup SSH Keys

```ruby
def setup_deployment_ssh_key(ssh)
  # Check for existing SSH key
  public_key_result = execute_command(ssh,
    "cat ~/.ssh/id_ed25519.pub 2>/dev/null || echo 'NO_KEY_FOUND'"
  )

  if public_key_result.include?('NO_KEY_FOUND')
    # Generate new key if none exists
    log("No SSH key found, generating new key...")
    execute_command(ssh,
      "ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N '' -C 'vantage-deployment-key'"
    )
    public_key_result = execute_command(ssh, "cat ~/.ssh/id_ed25519.pub")
  end

  # Add key to Dokku
  if public_key_result.present?
    public_key = public_key_result.strip

    # Check if key already in Dokku
    existing_keys = execute_command(ssh, "sudo dokku ssh-keys:list")

    if !existing_keys.include?(key_fingerprint)
      # Add key with unique name
      key_name = "deployment-#{Time.current.to_i}"
      execute_command(ssh,
        "echo '#{public_key}' | sudo dokku ssh-keys:add #{key_name}"
      )
      log("✓ SSH key added to Dokku successfully")
    else
      log("✓ SSH key already exists in Dokku")
    end
  end
end
```

**Why needed:**
- Dokku requires SSH key to accept `git push`
- Auto-generates key if not present
- Adds key to Dokku's authorized keys

#### 6. Push to Dokku

```ruby
# Add dokku remote
execute_command(ssh, "cd #{deploy_dir} && git remote add dokku dokku@#{@server.ip}:#{app_name}")

# Push to deploy (10 minute timeout)
log("Pushing to Dokku (this may take a few minutes)...")
deploy_output = execute_command(ssh,
  "cd #{deploy_dir} && GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no' git push dokku HEAD:main --force",
  timeout: 600
)

# Log deployment output
deploy_output.split("\n").each { |line| log("DEPLOY: #{line}") }
```

**What happens:**
1. Git push triggers Dokku's git hook
2. Dokku detects buildpack or Dockerfile
3. Builds Docker image
4. Creates/updates containers
5. Configures nginx proxy
6. Starts application

**Output includes:**
- Buildpack detection
- Build steps
- Release commands
- Container creation
- Application URL

#### 7. Verify Deployment

```ruby
def verify_deployment(ssh)
  log("Verifying deployment...")

  app_name = @deployment.dokku_app_name

  # Check if app is running
  ps_result = execute_command(ssh, "dokku ps:report #{app_name}")

  if ps_result.include?('running') || ps_result.include?('up')
    log("✓ App is running on Dokku")

    # Get app URL
    url_result = execute_command(ssh, "dokku url #{app_name}").strip
    if url_result.start_with?('http')
      log("✓ App URL: #{url_result}")
    end

    { success: true }
  else
    # App not running, check logs
    logs_result = execute_command(ssh, "dokku logs #{app_name} --tail 5")
    log("Recent logs: #{logs_result}")

    { success: false, message: "App may not be running properly" }
  end
end
```

**Verification checks:**
- Process status (running/stopped)
- Application URL availability
- Recent logs for errors

#### 8. Finalize Deployment

```ruby
# Determine final status
final_success = determine_deployment_success(result[:success])

# Update attempt
@deployment_attempt.update!(
  status: final_success ? 'success' : 'failed',
  completed_at: Time.current,
  logs: @logs.join("\n"),
  error_message: final_success ? nil : result[:error]
)

# Broadcast completion
broadcast_completion_status(final_success, result[:error])
```

**Updates:**
- Attempt status → 'success' or 'failed'
- Records completed_at timestamp
- Stores complete logs
- Broadcasts via ActionCable

---

## DeploymentAttempt Tracking

### Purpose

**CRITICAL PATTERN:** Every deployment creates a `DeploymentAttempt` record.

**Why:**
- Complete audit trail of all deployments
- Never lose deployment history
- Track success/failure rates
- Debug failed deployments
- Calculate average deployment time

### Model Structure

```ruby
class DeploymentAttempt < ApplicationRecord
  belongs_to :deployment

  validates :attempt_number, presence: true
  validates :status, inclusion: { in: %w[pending running success failed] }

  # Fields:
  # - attempt_number (integer) - Sequential attempt number
  # - status (string) - pending, running, success, failed
  # - started_at (datetime) - When deployment started
  # - completed_at (datetime) - When deployment finished
  # - logs (text) - Complete deployment logs
  # - error_message (string) - Error if failed

  def duration
    return nil unless started_at && completed_at
    completed_at - started_at
  end

  def duration_text
    return "N/A" unless duration
    "#{duration.to_i} seconds"
  end
end
```

### Creating Attempts

```ruby
def create_deployment_attempt
  next_attempt_number = @deployment.deployment_attempts.maximum(:attempt_number).to_i + 1

  @deployment.deployment_attempts.create!(
    attempt_number: next_attempt_number,
    status: 'pending'
  )
end
```

**Attempt numbers:**
- Auto-incremented: 1, 2, 3, ...
- Never reused
- Survives attempt deletion

### Lifecycle

```
pending
  │
  │ deployment.update!(status: 'running', started_at: Time.current)
  ▼
running
  │
  │ deployment.update!(status: 'success', completed_at: Time.current)
  ▼
success

OR

running
  │
  │ deployment.update!(status: 'failed', completed_at: Time.current, error_message: ...)
  ▼
failed
```

### Viewing Attempt History

```ruby
# Controller
@deployment_attempts = @deployment.deployment_attempts.order(attempt_number: :desc)

# View
@deployment_attempts.each do |attempt|
  puts "Attempt ##{attempt.attempt_number}: #{attempt.status} (#{attempt.duration_text})"
end
```

---

## Repository Cloning Strategies

### Deployment Methods

**Three supported methods:**

1. **Manual Git Push** (`manual`)
   - User pushes directly to `dokku@server:app`
   - No automatic deployments
   - Not handled by DeploymentService

2. **GitHub Repository** (`github_repo`)
   - Uses GitHub OAuth token
   - Supports private repositories
   - Requires LinkedAccount (GitHub)

3. **Public Repository** (`public_repo`)
   - Any public Git repository
   - No authentication required
   - Works with GitLab, Bitbucket, etc.

### Clone Strategy

**Primary approach:**
```bash
git clone -b <branch> <repo_url> <deploy_dir>
```

**Fallback approach (if branch-specific fails):**
```bash
git clone <repo_url> <deploy_dir>
cd <deploy_dir>
git checkout <branch>
```

**Why fallback needed:**
- Branch might not exist
- Default branch might have different name
- Empty repositories

### Unique Deploy Directories

**Pattern:** `/home/dokku/{app_name}-deploy-{timestamp}`

**Example:** `/home/dokku/myapp-deploy-1712012345`

**Benefits:**
- Parallel deployments don't conflict
- Easy to identify deployment directories
- Automatic cleanup after deployment

**Cleanup:**
```ruby
ensure
  # Always clean up temporary directory
  execute_command(ssh, "rm -rf #{deploy_dir}")
  log("Cleaned up temporary files")
end
```

---

## Git Authentication

### GitHub Private Repositories

**Requirements:**
1. User has LinkedAccount with GitHub
2. Account has valid OAuth access token
3. Repository URL is GitHub HTTPS format

**Authentication flow:**

```ruby
def prepare_authenticated_repo_url(repo_url)
  # Check if GitHub repo and user has GitHub account
  if repo_url.include?('github.com') &&
     @deployment.deployment_method == 'github_repo'

    github_account = @deployment.user.linked_accounts.find_by(provider: 'github')

    if github_account&.token_valid?
      # Convert to authenticated URL
      # FROM: https://github.com/username/repo.git
      # TO:   https://TOKEN@github.com/username/repo.git
      if repo_url.start_with?('https://github.com/')
        authenticated_url = repo_url.sub(
          'https://github.com/',
          "https://#{github_account.access_token}@github.com/"
        )
        log("Using GitHub token authentication for private repository")
        return authenticated_url
      end
    else
      log("⚠️ Warning: GitHub repository detected but no valid GitHub token found")
    end
  end

  # Return original URL
  repo_url
end
```

**OAuth token:**
- Stored encrypted in `linked_accounts` table
- Validated before use
- Embedded in HTTPS URL for authentication

### Public Repositories

**No authentication needed:**
```ruby
# Just clone directly
git clone https://github.com/user/public-repo.git /tmp/deploy
```

**Supported:**
- GitHub public repos
- GitLab public repos
- Bitbucket public repos
- Any public Git server

### SSH Git URLs

**NOT CURRENTLY SUPPORTED:**
```ruby
# ❌ Won't work
git@github.com:user/repo.git

# ✅ Use HTTPS instead
https://github.com/user/repo.git
```

**Why:**
- Requires SSH key exchange
- More complex authentication
- HTTPS simpler for automated deployments

---

## Dokku App Creation

### App Naming

**Pattern:** Auto-generated on Deployment creation

```ruby
# Model: app/models/deployment.rb
before_validation :generate_dokku_app_name, on: :create

def generate_dokku_app_name
  return if dokku_app_name.present?

  max_attempts = 10
  attempts = 0

  begin
    attempts += 1

    # Generate: adjective-noun-noun
    adjective = ADJECTIVES.sample
    noun1 = NOUNS.sample
    noun2 = NOUNS.sample

    # Ensure unique nouns
    noun2 = NOUNS.sample while noun1 == noun2

    generated_name = "#{adjective}-#{noun1}-#{noun2}"

    # Check uniqueness
    unless Deployment.exists?(dokku_app_name: generated_name)
      self.dokku_app_name = generated_name
      break
    end
  end while attempts < max_attempts

  # Fallback to timestamp-based name
  if dokku_app_name.blank?
    timestamp = Time.current.to_i
    self.dokku_app_name = "app-#{timestamp}"
  end
end
```

**Examples:**
- `brave-butterfly-kingdom`
- `ancient-mountain-river`
- `cosmic-dragon-forest`
- Fallback: `app-1712012345`

**Word lists:**
```ruby
ADJECTIVES = %w[
  ancient brave calm clever bold bright cosmic deep elegant
  fierce gentle golden happy infinite jolly kind light mighty
  noble peaceful quiet radiant serene swift wise wonderful
  arctic autumn blazing crystal dancing electric frozen glowing
  misty mystic ocean silver storm sunset thunder winter stellar
  lunar royal emerald crimson azure violet amber bronze copper
]

NOUNS = %w[
  butterfly kingdom mountain river forest ocean star moon dream
  whisper thunder lightning rainbow phoenix dragon eagle wolf
  bear lion tiger elephant dolphin whale shark turtle dove hawk
  falcon swan crystal diamond ruby emerald sapphire pearl jade
  amber opal garnet castle fortress tower bridge valley meadow
  garden waterfall lagoon island continent plateau canyon desert
  oasis glacier volcano wisdom courage honor justice truth beauty
  grace strength harmony peace
]
```

### Dokku App Creation

**Idempotent command:**
```bash
dokku apps:create myapp
```

**If app exists:**
```
!     Name already exists
```

**Service handles both cases:**
```ruby
def create_dokku_app(ssh)
  app_name = @deployment.dokku_app_name

  # Check if app exists
  result = execute_command(ssh,
    "dokku apps:list | grep '^#{app_name}$' || echo 'NOT_FOUND'"
  )

  if result.include?('NOT_FOUND')
    # Create new app
    execute_command(ssh, "dokku apps:create #{app_name}")
    log("✓ Dokku app created successfully")
  else
    # App exists, skip creation
    log("✓ Dokku app already exists")
  end
end
```

**Safe to run multiple times!**

---

## Auto-Name Generation

### Deployment Names

**User-provided OR auto-generated:**

```ruby
# User provides name
deployment = Deployment.new(name: "My Production App")

# Or leave blank for auto-generation
deployment = Deployment.new
# => name: nil, but dokku_app_name auto-generated
```

**Normalization:**
```ruby
def normalize_dokku_app_name
  return unless dokku_app_name.present?

  self.dokku_app_name = dokku_app_name
    .downcase                    # Lowercase
    .gsub(/[^a-z0-9-]/, '-')     # Replace invalid chars with dashes
    .gsub(/-+/, '-')             # Collapse multiple dashes
    .gsub(/^-|-$/, '')           # Remove leading/trailing dashes
end
```

**Examples:**
```ruby
"My App!" => "my-app"
"test__deployment" => "test-deployment"
"APP-123" => "app-123"
```

### Database Names

**Similar pattern for databases:**

```ruby
# app/models/database_configuration.rb
before_validation :generate_database_name, on: :create

def generate_database_name
  return if database_name.present?

  adjective = ADJECTIVES.sample
  noun1 = NOUNS.sample
  noun2 = NOUNS.sample
  noun2 = NOUNS.sample while noun1 == noun2

  self.database_name = "#{adjective}-#{noun1}-#{noun2}"
end
```

**Examples:**
- `morning-forest-river`
- `golden-eagle-mountain`
- `serene-ocean-crystal`

---

## Deployment Verification

### Success Determination

**Complex logic with multiple indicators:**

```ruby
def determine_deployment_success(initial_success)
  logs_text = @logs.join("\n")

  # Critical failure patterns (DEFINITELY failed)
  critical_failure_patterns = [
    /failed to push.*refs/i,
    /permission denied.*publickey/i,
    /could not read from remote repository/i,
    /fatal.*could not read/i,
    /deployment.*failed/i,
    /build.*failed/i
  ]

  # Check for critical failures
  critical_failure_patterns.each do |pattern|
    return false if logs_text.match?(pattern)
  end

  # Success indicators (DEFINITELY succeeded)
  return true if logs_text.include?("✓ App is running on Dokku")
  return true if logs_text.include?("✓ Git push completed")
  return true if logs_text.include?("Everything up-to-date")

  # Fallback to initial success
  initial_success
end
```

**Success indicators (in priority order):**
1. "✓ App is running on Dokku" - Verified running
2. "✓ Git push completed" - Git push succeeded
3. "Everything up-to-date" - No changes needed
4. No critical failures + initial success

**Failure indicators:**
- "failed to push"
- "permission denied"
- "build failed"
- "deployment failed"

### Post-Deployment Checks

**Automatic checks after git push:**

```ruby
def verify_deployment(ssh)
  # 1. Check process status
  ps_result = execute_command(ssh, "dokku ps:report #{app_name}")

  if ps_result.include?('running') || ps_result.include?('up')
    log("✓ App is running on Dokku")

    # 2. Get app URL
    url_result = execute_command(ssh, "dokku url #{app_name}").strip
    if url_result.start_with?('http')
      log("✓ App URL: #{url_result}")
    end

    return { success: true }
  else
    # 3. Check recent logs for errors
    logs_result = execute_command(ssh, "dokku logs #{app_name} --tail 5")
    log("Recent logs: #{logs_result}")

    return { success: false, message: "App may not be running properly" }
  end
end
```

---

## Real-Time Progress

### Log Broadcasting

**Every log message broadcasts to ActionCable:**

```ruby
def log(message)
  # Clean UTF-8 encoding
  clean_message = sanitize_utf8(message)

  # Format with timestamp
  timestamp = Time.current.strftime("%H:%M:%S")
  formatted_message = "[#{timestamp}] #{clean_message}"

  # Store in logs array
  @logs << formatted_message

  # Log to Rails logger
  Rails.logger.info "[DeploymentService] #{clean_message}"

  # Update attempt logs in database (real-time)
  @deployment_attempt.update_column(:logs, @logs.join("\n"))

  # Broadcast via ActionCable
  ActionCable.server.broadcast("deployment_logs_#{@deployment.uuid}", {
    type: 'log_message',
    message: formatted_message,
    attempt_id: @deployment_attempt.id,
    attempt_number: @deployment_attempt.attempt_number,
    timestamp: Time.current.iso8601
  })

  # Also broadcast to attempt-specific channel
  ActionCable.server.broadcast("deployment_attempt_logs_#{@deployment_attempt.id}", {
    type: 'log_message',
    message: formatted_message,
    full_logs: @logs.join("\n"),
    timestamp: Time.current.iso8601
  })
end
```

**User sees:**
- Each log line as it's generated
- Timestamped messages
- Real-time progress (no refresh needed)

### Completion Broadcast

```ruby
def broadcast_completion_status(success, error_message = nil)
  # Deployment-level broadcast
  ActionCable.server.broadcast("deployment_logs_#{@deployment.uuid}", {
    type: 'deployment_completed',
    success: success,
    attempt_id: @deployment_attempt.id,
    attempt_number: @deployment_attempt.attempt_number,
    status: @deployment_attempt.status,
    duration: @deployment_attempt.duration_text,
    error_message: error_message,
    completed_at: Time.current.iso8601
  })

  # Attempt-level broadcast
  ActionCable.server.broadcast("deployment_attempt_logs_#{@deployment_attempt.id}", {
    type: 'attempt_completed',
    success: success,
    full_logs: @logs.join("\n"),
    completed_at: Time.current.iso8601
  })
end
```

**UI can:**
- Show success/failure badge
- Display deployment duration
- Hide progress indicator
- Show error message if failed

---

## Error Handling

### SSH Errors

```ruby
rescue Net::SSH::AuthenticationFailed => e
  error_msg = "Authentication failed. Please check your SSH key or password."
  log("ERROR: #{error_msg}")
  finalize_failed_attempt(error_msg)
  { success: false, error: error_msg }

rescue Net::SSH::ConnectionTimeout => e
  error_msg = "Connection timeout. Server may be unreachable."
  log("ERROR: #{error_msg}")
  finalize_failed_attempt(error_msg)
  { success: false, error: error_msg }

rescue StandardError => e
  log("ERROR: #{e.message}")
  finalize_failed_attempt(e.message)
  { success: false, error: e.message }
end
```

### Git Errors

**Clone failures:**
- Invalid repository URL
- Branch doesn't exist
- Authentication failed
- Repository doesn't exist

**Push failures:**
- SSH key not authorized
- Build failed
- Insufficient disk space
- Port already in use

### Deployment Failures

**Build failures:**
- Missing Procfile or Dockerfile
- Buildpack detection failed
- Compilation errors
- Test failures (if configured)

**Runtime failures:**
- Port binding errors
- Environment variables missing
- Database connection errors
- Crashed immediately after start

---

## Common Deployment Issues

### Issue 1: Authentication Failed

**Symptoms:**
- "Authentication failed" in logs
- Git clone fails

**Causes:**
- GitHub token expired/invalid
- Private repository but no token
- Wrong repository URL

**Solutions:**
```ruby
# Check GitHub linked account
github_account = user.linked_accounts.find_by(provider: 'github')
github_account&.token_valid?  # Should be true

# Re-link GitHub account
# Navigate to Linked Accounts → Connect GitHub
```

### Issue 2: Branch Not Found

**Symptoms:**
- "pathspec 'branch-name' did not match any file(s)"
- Clone succeeds but checkout fails

**Causes:**
- Branch doesn't exist
- Typo in branch name
- Default branch has different name

**Solutions:**
```ruby
# Service automatically falls back to default branch
# User sees warning in logs:
# "⚠️ Warning: Could not checkout branch 'feature', using default branch"

# Or update deployment with correct branch:
deployment.update(repository_branch: 'main')
```

### Issue 3: Build Failed

**Symptoms:**
- Git push succeeds
- Build fails
- "deployment failed" in logs

**Causes:**
- Syntax errors in code
- Missing dependencies
- Compilation errors
- Tests failing (if configured)

**Solutions:**
```bash
# Check deployment logs
dokku logs myapp --tail 100

# Check build logs
dokku logs myapp --tail 500 | grep "BUILD"

# Manually test locally
git clone <repo> && cd <repo>
docker build .
```

### Issue 4: App Not Running

**Symptoms:**
- Build succeeds
- Verification fails
- "App may not be running properly"

**Causes:**
- Application crashes on startup
- Port binding errors
- Missing environment variables
- Database connection errors

**Solutions:**
```bash
# Check app logs
dokku logs myapp --tail 100

# Check process status
dokku ps:report myapp

# Restart app
dokku ps:restart myapp

# Check environment variables
dokku config:show myapp
```

### Issue 5: Cleanup Failures

**Symptoms:**
- "Permission denied" during cleanup
- `/home/dokku` disk space growing

**Causes:**
- Deploy directory not removed
- SSH user lacks permissions

**Solutions:**
```bash
# Manually clean up
ssh user@server
rm -rf /home/dokku/*-deploy-*

# Check disk space
df -h /home/dokku
```

---

## Summary

### Key Takeaways

1. **DeploymentService orchestrates** entire deployment workflow
2. **DeploymentAttempt tracks** every deployment execution
3. **Auto-generated names** eliminate naming conflicts
4. **Real-time logs** via ActionCable for great UX
5. **Git authentication** supports GitHub private repos
6. **Idempotent operations** safe to retry
7. **Comprehensive error handling** with user-friendly messages
8. **Cleanup always runs** (in `ensure` block)

### Deployment Methods

| Method | Authentication | Use Case |
|--------|----------------|----------|
| Manual | User's SSH key | Advanced users, custom workflows |
| GitHub Repo | OAuth token | Private GitHub repositories |
| Public Repo | None | Public repositories (any Git server) |

### Success Criteria

**Deployment succeeds when:**
- ✅ Repository cloned successfully
- ✅ Git push to Dokku completed
- ✅ Docker build succeeded
- ✅ Application started and running
- ✅ Verification checks pass

**Deployment fails when:**
- ❌ Authentication error
- ❌ Clone/push failed
- ❌ Build errors
- ❌ Application crashes on start
- ❌ Verification checks fail

### Checklist for Successful Deployments

**Before deploying:**
- [ ] Server has Dokku installed
- [ ] Server connection status is 'connected'
- [ ] Repository URL is correct (HTTPS format)
- [ ] Branch exists in repository
- [ ] For private repos: GitHub account linked and valid
- [ ] Application has Dockerfile or supported buildpack

**After deploying:**
- [ ] Check deployment logs for errors
- [ ] Verify application is running: `dokku ps:report app`
- [ ] Test application URL in browser
- [ ] Check application logs: `dokku logs app`

### Related Documentation

- [CLAUDE.md](/CLAUDE.md) - DeploymentAttempt pattern
- [ARCHITECTURE.md](/docs/ARCHITECTURE.md) - Service layer design
- [ssh-integration.md](/docs/features/ssh-integration.md) - SSH command execution
- [real-time-updates.md](/docs/features/real-time-updates.md) - Log broadcasting

---

**Deployments are the core value proposition of Vantage-Dokku. Make them reliable!**
