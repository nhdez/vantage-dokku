# Vantage-Dokku Architecture

## System Overview

Vantage-Dokku is a web-based management platform for Dokku PaaS (Platform as a Service) deployments. It provides a centralized dashboard for managing multiple Dokku servers, deploying applications, configuring databases, managing SSL certificates, and monitoring application health.

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       Web Browser                           │
│  (User Interface + WebSocket Client + JavaScript/Stimulus)  │
└─────────────────┬───────────────────────────────────────────┘
                  │
                  │ HTTPS/WSS
                  ▼
┌─────────────────────────────────────────────────────────────┐
│                   Rails Web Server (Puma)                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Controllers Layer                      │   │
│  │  (Request handling, authorization, routing)          │   │
│  └───────────────────┬─────────────────────────────────┘   │
│                      │                                       │
│  ┌──────────────────┼─────────────────────────────────┐   │
│  │              Services Layer                         │   │
│  │  SshConnectionService │ DeploymentService │ etc     │   │
│  └───────────────────┬─────────────────────────────────┘   │
│                      │                                       │
│  ┌──────────────────┴─────────────────────────────────┐   │
│  │              Models Layer (Active Record)           │   │
│  │  User │ Server │ Deployment │ Domain │ etc         │   │
│  └───────────────────┬─────────────────────────────────┘   │
└────────────────────┬─┴─────────────────────────────────────┘
                     │
        ┌───────────┼─────────────┐
        │           │             │
        ▼           ▼             ▼
  ┌─────────┐ ┌─────────┐  ┌─────────────┐
  │PostgreSQL│ │SolidQueue│  │ ActionCable │
  │ Primary  │ │  Worker  │  │ (SolidCable)│
  └─────────┘ └─────────┘  └─────────────┘
        │
        │ Background Jobs
        ▼
┌──────────────────────────────────────────────┐
│         Background Job Processor             │
│  ┌──────────────────────────────────────┐   │
│  │        Job Layer (SolidQueue)        │   │
│  │  DeploymentJob │ HealthCheckJob │etc │   │
│  └──────────────────┬───────────────────┘   │
└──────────────────────┼──────────────────────┘
                       │
                       │ SSH Connections
                       ▼
          ┌───────────────────────────┐
          │   Remote Dokku Servers    │
          │  (SSH over port 22/custom)│
          │                           │
          │  ┌─────────────────────┐  │
          │  │   Dokku Apps        │  │
          │  │  (Docker containers) │  │
          │  └─────────────────────┘  │
          └───────────────────────────┘

External Services:
  - GitHub API (repository access, OAuth)
  - Google OAuth (user authentication)
  - OSV API (vulnerability details)
  - SMTP Server (email notifications)
```

---

## Technology Stack

### Backend Framework
- **Ruby 3.4.5** - Programming language
- **Rails 8.0.2** - Full-stack web application framework
- **PostgreSQL** - Relational database

### Rails 8 Modern Stack
- **SolidQueue** - Database-backed job queue (replaces Sidekiq/Resque)
- **SolidCache** - Database-backed caching (replaces Redis cache)
- **SolidCable** - Database-backed ActionCable (replaces Redis pub/sub)

**Why Solid* gems?**
- Eliminates Redis dependency (one less service to manage)
- All data persists in PostgreSQL
- Simplifies deployment and scaling
- Production-ready for moderate traffic applications

### Frontend Stack
- **Hotwire**
  - **Turbo Rails** - SPA-like navigation without full page reloads
  - **Stimulus.js** - Lightweight JavaScript framework for sprinkles of interactivity
- **Importmap Rails** - ES module imports (no Node.js/webpack required)
- **Propshaft** - Modern asset pipeline (replaces Sprockets)
- **Bootstrap 5 + Material Design Bootstrap** - UI framework
- **Redcarpet** - Markdown rendering (vulnerability reports)

### Authentication & Authorization
- **Devise** - User authentication (email/password)
- **OmniAuth** - OAuth integration framework
- **omniauth-google-oauth2** - Google OAuth provider
- **Pundit** - Policy-based authorization
- **Rolify** - Role management (admin, moderator)

### Infrastructure & Communication
- **Net::SSH** - SSH client for remote command execution
- **Ed25519 & BCrypt PBKDF** - SSH key support
- **Faraday** - HTTP client (GitHub API, OSV API)
- **Octokit** - GitHub API client
- **Pagy** - Lightweight pagination
- **Ransack** - Search and filtering

### Development & Security
- **Brakeman** - Rails security vulnerability scanner
- **RuboCop** - Ruby code linter
- **Better Errors** - Enhanced development error pages
- **Letter Opener** - Email preview in development

---

## Component Architecture

### 1. Web Layer (MVC Pattern)

#### Controllers (`/app/controllers`)
- **Purpose:** Handle HTTP requests, authorize actions, coordinate services
- **Patterns:**
  - Inherit from `ApplicationController`
  - Include `ActivityTrackable` for audit logging
  - Include `Toastable` for notifications
  - Use Pundit for authorization: `authorize @resource`
  - Delegate business logic to services/jobs

**Key Controllers:**
- `ServersController` - Server CRUD, connection testing, firewall
- `DeploymentsController` - Deployment CRUD, domains, SSL, environment variables
- `SshKeysController` - SSH key management
- `LinkedAccountsController` - OAuth account linking
- `Admin::*Controllers` - Admin dashboard, users, activity logs

#### Views (`/app/views`)
- **ERB templates** with Turbo Frames/Streams
- **Partials** for reusable components
- **Helpers** for view logic
- **Real-time updates** via Turbo Streams (ActionCable broadcasts)

#### Models (`/app/models`)
**Purpose:** Data persistence, validations, relationships, business rules

**Key Models:**
```ruby
User          # Devise authentication, Rolify roles
  └─ Server   # Remote Dokku servers
      └─ Deployment  # Applications on servers
          ├─ Domain                 # Custom domains + SSL
          ├─ DatabaseConfiguration  # Managed databases
          ├─ EnvironmentVariable    # App configuration
          ├─ PortMapping            # Port exposure
          ├─ DeploymentAttempt      # Deployment history
          └─ ApplicationHealth      # Health check results
```

**Critical Patterns:**
- UUID primary keys (Server, Deployment) for security
- Encrypted attributes (Server#password, LinkedAccount#access_token)
- Scoped validations (unique names per user)
- Auto-generated names (Deployment: "brave-butterfly-kingdom")

---

### 2. Service Layer (`/app/services`)

**Purpose:** Encapsulate complex business logic, SSH operations, external API calls

#### SshConnectionService (2,831 lines) ⭐️ MOST CRITICAL
**File:** `/app/services/ssh_connection_service.rb`

**Responsibilities:**
- SSH connection management to Dokku servers
- Dokku installation and updates
- App creation and deletion
- Domain and SSL configuration
- Database plugin management
- Firewall (UFW) configuration
- Environment variable management
- Port mapping operations
- Health diagnostics
- Log streaming

**Characteristics:**
- Multiple timeout constants for different operations
- Comprehensive error handling (Net::SSH exceptions)
- Updates `server.last_connected_at` on successful connections
- Returns consistent hash structure: `{ success:, error:, output:, ... }`
- UTF-8 sanitization for SSH output

**Connection Flow:**
```
1. Get connection details from server model
   ├─ IP, username, port
   ├─ SSH keys (from ENV or AppSetting)
   └─ Password (fallback authentication)

2. Establish SSH connection with timeout
   └─ Net::SSH.start(host, username, ssh_options)

3. Execute command(s)
   ├─ Use appropriate timeout constant
   └─ Stream output for long operations

4. Handle errors
   ├─ AuthenticationFailed → Check SSH key/password
   ├─ ConnectionTimeout → Server unreachable
   ├─ ECONNREFUSED → SSH service down
   └─ EHOSTUNREACH → Network issue

5. Update server metadata
   └─ last_connected_at, dokku_version, system info
```

#### Other Services

**DeploymentService** (480 lines)
- Orchestrates deployments from repositories
- Creates DeploymentAttempt records
- Broadcasts progress via ActionCable
- Verifies deployment success

**ApplicationHealthService**
- HTTP health checks
- Response time measurement
- Uptime/downtime tracking

**SslVerificationService**
- Domain SSL certificate validation
- Certificate info extraction
- Expiration tracking

**GitHubService**
- OAuth token validation
- Repository listing
- Branch fetching

**OsvScannerParser**
- Parses OSV Scanner JSON output
- Extracts CVE details
- Maps severity levels

---

### 3. Job Layer (`/app/jobs`)

**Purpose:** Asynchronous background processing using SolidQueue

**Key Jobs:**

| Job | Purpose | Frequency |
|-----|---------|-----------|
| `DeploymentJob` | Orchestrates Git deployments | On-demand |
| `CreateDokkuAppJob` | Creates Dokku apps | On-demand |
| `ApplicationHealthCheckJob` | Monitors app health | Every 5 minutes |
| `HealthNotificationJob` | Sends downtime alerts | On health failure |
| `UpdateServerJob` | Updates server info | On-demand |
| `UpdateDomainsJob` | Syncs domain/SSL status | On-demand |
| `UpdateEnvironmentJob` | Syncs environment variables | On-demand |
| `VulnerabilityScannerJob` | Runs security scans | On-demand |
| `DeploymentDeletionJob` | Deletes Dokku apps | On-demand |
| `DatabaseConfigurationJob` | Configures databases | On-demand |

**Job Pattern:**
1. Update model status (`deployment.update!(status: 'deploying')`)
2. Broadcast start to ActionCable
3. Call service object to perform work
4. Stream progress updates via ActionCable
5. Update final status and broadcast completion

**Recurring Jobs:**
```ruby
# config/initializers/recurring_jobs.rb
SolidQueue::RecurringTask.create!(
  key: "health_checks",
  schedule: "*/5 * * * *",  # Every 5 minutes
  command: "ApplicationHealthCheckJob.perform_later"
)
```

**Development vs Production:**
```ruby
if Rails.env.development?
  MyJob.perform_now(model)   # Synchronous for faster feedback
else
  MyJob.perform_later(model) # Asynchronous in production
end
```

---

### 4. Real-Time Communication Layer

#### ActionCable Channels (`/app/channels`)

**Purpose:** WebSocket-based real-time updates for long-running operations

**Key Channels:**

| Channel | Purpose |
|---------|---------|
| `DeploymentLogsChannel` | Stream deployment logs |
| `ServerLogsChannel` | Stream server command output |
| `CommandExecutionChannel` | Execute commands and stream results |
| `DatabaseConfigurationChannel` | Database setup progress |
| `UpdateDomainsChannel` | Domain/SSL operation progress |
| `UpdateEnvironmentChannel` | Environment variable sync progress |
| `TestConnectionChannel` | Server connection test results |
| `DeploymentDeletionChannel` | App deletion progress |
| `ScannerInstallationChannel` | OSV Scanner install progress |
| `DokkuInstallationChannel` | Dokku install progress |
| `ServerUpdateChannel` | Server update progress |

**Channel Pattern:**
```ruby
class DeploymentLogsChannel < ApplicationCable::Channel
  def subscribed
    deployment = Deployment.find_by(uuid: params[:uuid])
    stream_from "deployment_logs_#{deployment.uuid}"
  end
end
```

**Broadcasting Pattern:**
```ruby
ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", {
  type: 'data',
  message: sanitize_utf8(log_line),
  timestamp: Time.current
})
```

**Client-Side (JavaScript/Stimulus):**
```javascript
// Stimulus controller subscribes to channel
consumer.subscriptions.create(
  { channel: "DeploymentLogsChannel", uuid: deploymentUuid },
  {
    received(data) {
      if (data.type === 'data') {
        appendLogLine(data.message);
      }
    }
  }
);
```

#### Production Configuration

**SolidCable** (`config/cable.yml`):
```yaml
production:
  adapter: solid_cable
  connects_to:
    database:
      writing: cable
```

**Why SolidCable?**
- No Redis dependency
- Persistent WebSocket data in PostgreSQL
- Supports multiple web server processes
- Automatic cleanup of stale connections

---

### 5. Data Layer

#### Database Architecture

**Primary Database:**
- PostgreSQL 12+
- Stores all application data
- Handles high read/write throughput

**Multi-Database Setup (Production):**
```yaml
production:
  primary:      # Main application data
  cache:        # SolidCache tables
  queue:        # SolidQueue job tables
  cable:        # SolidCable connection tables
```

**All databases connect to the same PostgreSQL instance using different schemas.**

#### Key Tables

**Core Tables:**
- `users` - Authentication (Devise)
- `servers` - Remote Dokku servers
- `deployments` - Applications
- `domains` - Custom domains + SSL
- `database_configurations` - Managed databases
- `environment_variables` - App configuration
- `port_mappings` - Port exposure

**Audit Tables:**
- `activity_logs` - User action audit trail
- `deployment_attempts` - Complete deployment history
- `application_healths` - Health check results

**Security Tables:**
- `ssh_keys` - User SSH public keys
- `linked_accounts` - OAuth accounts (encrypted tokens)

**Monitoring Tables:**
- `vulnerability_scans` - Security scan results
- `vulnerabilities` - Individual CVEs

**SolidQueue Tables (separate schema):**
- `solid_queue_jobs` - Pending/running jobs
- `solid_queue_failed_executions` - Failed jobs
- `solid_queue_recurring_tasks` - Scheduled jobs
- `solid_queue_processes` - Worker processes

**SolidCable Tables (separate schema):**
- `solid_cable_messages` - WebSocket messages

---

## External Integrations

### 1. Dokku Servers (SSH)

**Protocol:** SSH (typically port 22)
**Authentication:** SSH keys + password fallback
**Commands:** Dokku CLI commands via SSH

**Common Operations:**
```bash
dokku apps:create myapp
dokku apps:destroy myapp
dokku config:set myapp KEY=value
dokku domains:add myapp example.com
dokku letsencrypt:enable myapp
dokku postgres:create myapp-db
dokku postgres:link myapp-db myapp
```

**Error Handling:**
- Connection timeouts (server unreachable)
- Authentication failures (invalid SSH key/password)
- Command failures (Dokku errors)

### 2. GitHub API

**Purpose:** Repository access, OAuth authentication
**Client:** Octokit gem
**Authentication:** OAuth tokens (stored encrypted)

**Operations:**
- List user repositories
- Fetch repository branches
- Validate OAuth tokens
- Check repository access

**Rate Limiting:**
- Authenticated: 5,000 requests/hour
- Unauthenticated: 60 requests/hour

### 3. Google OAuth

**Purpose:** User authentication
**Provider:** omniauth-google-oauth2
**Scopes:** profile, email

**Flow:**
1. User clicks "Sign in with Google"
2. Redirect to Google OAuth
3. User authorizes application
4. Callback with authorization code
5. Exchange for access token
6. Create/update user account
7. Create linked account with encrypted token

### 4. OSV (Open Source Vulnerabilities) API

**Purpose:** Vulnerability details for CVEs
**Endpoint:** `https://api.osv.dev/v1/vulns/{id}`
**Rate Limiting:** None specified

**Usage:**
- Fetch detailed CVE information
- Get severity scores (CVSS)
- Retrieve affected package versions
- Display formatted vulnerability reports

### 5. SMTP Server

**Purpose:** Email notifications (health alerts, password resets)
**Configuration:** Dynamic (stored in database via AppSetting)

**Email Types:**
- Welcome emails (Devise confirmable)
- Password reset instructions
- Health check failure notifications
- Admin notifications

---

## Security Architecture

### 1. Authentication Flow

**Primary: Email + Password (Devise)**
```
1. User submits email/password
2. Devise validates credentials
3. BCrypt verifies password hash
4. Session created (encrypted cookie)
5. Activity log created (IP, user agent)
```

**Secondary: Google OAuth**
```
1. User clicks "Sign in with Google"
2. Redirect to Google OAuth consent screen
3. Google returns authorization code
4. Exchange code for access token
5. Fetch user profile from Google
6. Create/update User and LinkedAccount
7. Session created
```

### 2. Authorization (Pundit)

**Policy-Based Authorization:**
```ruby
# app/policies/deployment_policy.rb
class DeploymentPolicy < ApplicationPolicy
  def show?
    user.admin? || record.user == user
  end

  def update?
    user.admin? || record.user == user
  end

  def destroy?
    user.admin? || record.user == user
  end

  class Scope < Scope
    def resolve
      if user.admin?
        scope.all  # Admins see all deployments
      else
        scope.where(user: user)  # Users see only their deployments
      end
    end
  end
end
```

**Every controller action uses `authorize @resource`**

### 3. Data Encryption

**Active Record Encryption:**
```ruby
# app/models/server.rb
encrypts :password, deterministic: false

# app/models/linked_account.rb
encrypts :access_token, deterministic: false
```

**Encryption Keys:**
- Stored in `config/credentials.yml.enc` (production)
- Or `ACTIVE_RECORD_ENCRYPTION_*` ENV variables
- Generated with `rails db:encryption:init`

**How it works:**
- Transparent encryption/decryption
- Data encrypted at rest in database
- Cannot query encrypted fields directly

### 4. SSH Key Security

**Storage:**
- Public keys stored in `ssh_keys` table
- Private keys:
  - Option 1: AppSetting (database, encrypted)
  - Option 2: ENV variable (`DOKKU_SSH_KEY_PATH`)

**File Permissions:**
```ruby
File.chmod(0600, private_key_path)  # -rw------- (owner only)
```

**Temporary Key Files:**
- Created on-demand for SSH connections
- Stored in secure directory
- Deleted after use

### 5. Activity Logging

**All administrative actions logged:**
- User ID, timestamp, IP address, user agent
- Controller, action, parameters (sensitive data filtered)

**Filtered Parameters:**
- `password`, `password_confirmation`
- `current_password`, `smtp_password`
- `access_token`, `refresh_token`

**Retention:**
- Logs preserved even after user/resource deletion
- Can be queried for audits

### 6. Content Security

**Parameter Filtering:**
```ruby
# config/initializers/filter_parameter_logging.rb
Rails.application.config.filter_parameters += [
  :password, :password_confirmation, :current_password,
  :smtp_password, :access_token, :refresh_token,
  :private_key, :secret
]
```

**SQL Injection Protection:**
- Active Record parameterized queries
- Never use raw SQL with user input

**XSS Protection:**
- ERB auto-escaping by default
- Use `sanitize` helper for HTML content

---

## Scalability Considerations

### Vertical Scaling (Single Server)

**Current Architecture Supports:**
- Moderate traffic (1,000-10,000 requests/day)
- 10-50 concurrent users
- 10-100 managed Dokku servers
- 100-1,000 deployments

**Bottlenecks:**
- SSH connection pooling (sequential SSH operations)
- Database connections (PostgreSQL connection limit)
- Worker process capacity (SolidQueue concurrent jobs)

### Horizontal Scaling (Multiple Servers)

**To scale horizontally:**

1. **Web Servers:**
   - Run multiple Puma processes behind load balancer
   - Shared session store (encrypted cookies work out-of-the-box)
   - SolidCable handles multi-process ActionCable

2. **Worker Processes:**
   - Scale SolidQueue workers independently
   - Configure worker pool size in `config/queue.yml`
   - Jobs automatically distributed across workers

3. **Database:**
   - PostgreSQL read replicas for queries
   - Primary for writes
   - Connection pooling (PgBouncer)

4. **Caching:**
   - SolidCache already in database (scales with PostgreSQL)
   - Consider Redis cache for high-traffic scenarios

**Load Balancer Configuration:**
- Sticky sessions not required (encrypted cookies)
- WebSocket support required for ActionCable
- Health check endpoint: `/up`

### Performance Optimizations

**Database:**
- Indexes on frequently queried columns (uuid, user_id, status)
- N+1 query prevention (`includes`, `eager_load`)
- Background jobs for expensive queries

**SSH Connections:**
- Connection reuse within single operation
- Timeout management (prevent hanging connections)
- Concurrent SSH operations where possible (future enhancement)

**ActionCable:**
- Stream only necessary data
- Unsubscribe when not needed
- Limit message size (paginate large logs)

**Asset Delivery:**
- Propshaft digests for cache busting
- CDN for static assets (CSS, JS, images)
- Gzip compression enabled

---

## Deployment Architecture

### Production Deployment (Dokku)

**Irony:** Vantage-Dokku is designed to be deployed ON Dokku (managing itself!)

```
┌─────────────────────────────────┐
│   Dokku Server (Primary)        │
│                                  │
│  ┌────────────────────────────┐ │
│  │   Vantage-Dokku App        │ │
│  │   (Docker Container)       │ │
│  │                             │ │
│  │  - Web Process (Puma)      │ │
│  │  - Worker Process (Queue)  │ │
│  └────────────────────────────┘ │
│                                  │
│  ┌────────────────────────────┐ │
│  │   PostgreSQL Plugin        │ │
│  │   (vantage-db)             │ │
│  └────────────────────────────┘ │
│                                  │
│  ┌────────────────────────────┐ │
│  │   Let's Encrypt Plugin     │ │
│  │   (SSL certificates)       │ │
│  └────────────────────────────┘ │
└─────────────────────────────────┘
        │
        │ Manages
        ▼
┌─────────────────────────────────┐
│   Dokku Servers (Managed)       │
│   - Server 1                    │
│   - Server 2                    │
│   - Server N                    │
└─────────────────────────────────┘
```

**Procfile:**
```
web: bundle exec puma -C config/puma.rb
worker: bundle exec rake solid_queue:start
```

**Scaling:**
```bash
dokku ps:scale vantage web=2 worker=1
```

### Environment Configuration

**Required ENV Variables:**
- `RAILS_ENV=production`
- `SECRET_KEY_BASE` (generate with `rails secret`)
- `APP_HOST` (e.g., `vantage.example.com`)
- `DATABASE_URL` (auto-set by Dokku PostgreSQL plugin)

**Optional ENV Variables:**
- `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET`
- `SMTP_ADDRESS`, `SMTP_PORT`, `SMTP_USERNAME`, `SMTP_PASSWORD`
- `DOKKU_LETSENCRYPT_EMAIL`
- `REDIS_URL` (optional, SolidQueue doesn't require it)

---

## Architecture Decision Records (ADRs)

### ADR-001: Use SolidQueue Instead of Sidekiq

**Date:** Project inception
**Status:** Accepted

**Context:**
Background job processing needed for deployments, health checks, scans.

**Decision:**
Use SolidQueue (Rails 8) instead of Sidekiq.

**Consequences:**
- ✅ No Redis dependency (simpler deployment)
- ✅ All data persists in PostgreSQL
- ✅ Native Rails 8 integration
- ❌ Less mature than Sidekiq (fewer features)
- ❌ May not scale as well for extremely high job volumes

---

### ADR-002: Use UUIDs for Public Routes

**Date:** Project inception
**Status:** Accepted

**Context:**
Need secure, non-enumerable URLs for servers and deployments.

**Decision:**
Use UUIDs as route parameters instead of database IDs.

**Consequences:**
- ✅ Security: Cannot enumerate resources
- ✅ Privacy: Database size not revealed
- ✅ Future-proof: Can change ID strategy without breaking URLs
- ❌ Slightly longer URLs
- ❌ Additional database column (uuid)

---

### ADR-003: Use SSH Instead of Dokku API

**Date:** Project inception
**Status:** Accepted

**Context:**
Need to communicate with Dokku servers. Dokku has CLI but no official REST API.

**Decision:**
Use SSH connections to execute Dokku CLI commands.

**Consequences:**
- ✅ Works with all Dokku versions
- ✅ Full access to Dokku features
- ✅ No additional Dokku plugins required
- ❌ SSH connection overhead
- ❌ Complex error handling
- ❌ UTF-8 encoding issues require sanitization

---

### ADR-004: Use SolidCable for ActionCable

**Date:** Project inception
**Status:** Accepted

**Context:**
Need real-time updates for long-running operations. ActionCable requires pub/sub backend.

**Decision:**
Use SolidCable (database-backed) instead of Redis.

**Consequences:**
- ✅ Consistent with SolidQueue choice
- ✅ No Redis dependency
- ✅ Works with multiple web server processes
- ❌ More database load (additional queries for pub/sub)
- ❌ May not scale as well as Redis for very high message volumes

---

## Future Architecture Considerations

### Potential Enhancements

1. **API Layer:**
   - Add RESTful API with authentication (API tokens)
   - Enable programmatic management of servers/deployments
   - Webhook support for deployment events

2. **Multi-Tenancy:**
   - Organization/team model
   - Shared servers across team members
   - Role-based permissions at team level

3. **SSH Connection Pooling:**
   - Reuse SSH connections across operations
   - Reduce connection overhead
   - Improve performance for rapid operations

4. **Caching Layer:**
   - Cache Dokku command outputs (apps list, config vars)
   - Invalidate on changes
   - Reduce SSH roundtrips

5. **Monitoring Dashboard:**
   - Real-time server metrics (CPU, RAM, disk)
   - Application metrics (request rate, response time)
   - Alert rules and notifications

6. **Backup Management:**
   - Automated database backups
   - Application file backups
   - Backup restoration interface

---

## Conclusion

Vantage-Dokku's architecture prioritizes **simplicity, security, and maintainability**:

- **Simplicity:** Rails 8 Solid* gems eliminate Redis dependency
- **Security:** UUID routing, encrypted credentials, activity logging, Pundit authorization
- **Maintainability:** Service objects, background jobs, real-time updates, comprehensive error handling

The architecture is designed for **moderate-scale deployments** (10-100 servers, 100-1,000 applications) with room to scale horizontally when needed.

**Core Architectural Principles:**
1. Convention over configuration (Rails way)
2. Security by default (UUIDs, encryption, authorization)
3. Explicit error handling (SSH operations never fail silently)
4. Audit everything (activity logs, deployment attempts)
5. Real-time feedback (ActionCable for long operations)
6. Background processing (never block web requests)

For more details, see:
- `/CLAUDE.md` - Critical patterns and conventions
- `/docs/CONVENTIONS.md` - Code style guide
- `/docs/features/*.md` - Feature-specific architecture
