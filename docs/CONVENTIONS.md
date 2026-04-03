# Coding Conventions and Patterns

This document outlines the coding standards, patterns, and conventions used in the Vantage-Dokku project. Following these conventions ensures consistency, maintainability, and prevents common mistakes.

---

## Table of Contents

1. [Naming Conventions](#naming-conventions)
2. [File Organization](#file-organization)
3. [Model Patterns](#model-patterns)
4. [Controller Patterns](#controller-patterns)
5. [Service Object Patterns](#service-object-patterns)
6. [Background Job Patterns](#background-job-patterns)
7. [ActionCable Channel Patterns](#actioncable-channel-patterns)
8. [View and Partial Organization](#view-and-partial-organization)
9. [JavaScript and Stimulus Conventions](#javascript-and-stimulus-conventions)
10. [Testing Conventions](#testing-conventions)
11. [Code Style and Best Practices](#code-style-and-best-practices)

---

## Naming Conventions

### Models

**Rule:** Singular, CamelCase
```ruby
# ✅ CORRECT
class Server < ApplicationRecord
class Deployment < ApplicationRecord
class DatabaseConfiguration < ApplicationRecord

# ❌ WRONG
class Servers < ApplicationRecord  # Plural
class deployment < ApplicationRecord  # lowercase
```

### Controllers

**Rule:** Plural, CamelCase, ends with `Controller`
```ruby
# ✅ CORRECT
class ServersController < ApplicationController
class DeploymentsController < ApplicationController
class SshKeysController < ApplicationController

# ❌ WRONG
class ServerController < ApplicationController  # Singular
```

### Services

**Rule:** Singular, descriptive noun, ends with `Service`
```ruby
# ✅ CORRECT
class SshConnectionService
class DeploymentService
class ApplicationHealthService

# ❌ WRONG
class Ssh  # Missing "Service"
class DeploymentManager  # Use "Service" not "Manager"
```

### Background Jobs

**Rule:** Descriptive action, ends with `Job`
```ruby
# ✅ CORRECT
class DeploymentJob < ApplicationJob
class CreateDokkuAppJob < ApplicationJob
class ApplicationHealthCheckJob < ApplicationJob

# ❌ WRONG
class Deploy < ApplicationJob  # Missing "Job"
class DeploymentWorker < ApplicationJob  # Use "Job" not "Worker"
```

### ActionCable Channels

**Rule:** Descriptive noun/action, ends with `Channel`
```ruby
# ✅ CORRECT
class DeploymentLogsChannel < ApplicationCable::Channel
class CommandExecutionChannel < ApplicationCable::Channel

# ❌ WRONG
class Deployment < ApplicationCable::Channel  # Missing "Channel"
```

### Database Tables

**Rule:** Snake_case, plural
```sql
-- ✅ CORRECT
servers
deployments
environment_variables

-- ❌ WRONG
Server  -- CamelCase
deployment  -- Singular
environmentVariables  -- camelCase
```

### Database Columns

**Rule:** Snake_case
```ruby
# ✅ CORRECT
user_id
created_at
dokku_app_name
deployment_status

# ❌ WRONG
userId  # camelCase
CreatedAt  # CamelCase
dokkuAppName  # camelCase
```

---

## File Organization

### Project Structure

```
app/
├── channels/           # ActionCable channels (WebSocket communication)
├── controllers/        # Request handlers
│   ├── concerns/       # Shared controller logic (mixins)
│   ├── admin/          # Admin-namespaced controllers
│   └── users/          # Devise overrides (sessions, registrations, etc.)
├── helpers/            # View helpers
├── jobs/               # Background jobs (SolidQueue)
├── mailers/            # Email senders
├── models/             # Data models (Active Record)
│   └── concerns/       # Shared model logic (mixins)
├── policies/           # Authorization policies (Pundit)
├── services/           # Business logic services
└── views/              # ERB templates
    ├── layouts/        # Layout templates
    ├── shared/         # Shared partials
    ├── deployments/    # Deployment views
    ├── servers/        # Server views
    └── admin/          # Admin views

config/
├── initializers/       # Rails initializers
├── locales/            # I18n translation files
└── environments/       # Environment-specific configs

db/
├── migrate/            # Database migrations
├── seeds.rb            # Seed data
├── schema.rb           # Generated schema (don't edit manually)
├── queue_schema.rb     # SolidQueue schema
├── cable_schema.rb     # SolidCable schema
└── cache_schema.rb     # SolidCache schema

test/
├── models/             # Model tests
├── controllers/        # Controller tests
├── jobs/               # Job tests
├── system/             # System/integration tests
└── fixtures/           # Test data
```

### File Naming

**Controllers:**
```
app/controllers/servers_controller.rb
app/controllers/admin/users_controller.rb
```

**Models:**
```
app/models/server.rb
app/models/deployment.rb
```

**Services:**
```
app/services/ssh_connection_service.rb
app/services/deployment_service.rb
```

**Jobs:**
```
app/jobs/deployment_job.rb
app/jobs/create_dokku_app_job.rb
```

**Views:**
```
app/views/deployments/show.html.erb
app/views/servers/_form.html.erb  # Partials start with underscore
app/views/shared/_navbar.html.erb
```

**Tests:**
```
test/models/server_test.rb
test/controllers/servers_controller_test.rb
```

---

## Model Patterns

### 1. UUID Routing (CRITICAL)

**ALWAYS use UUIDs for public routes, NEVER database IDs.**

```ruby
class Server < ApplicationRecord
  # Validations
  validates :uuid, presence: true, uniqueness: true

  # Callbacks
  before_validation :generate_uuid, on: :create

  # URL parameter
  def to_param
    uuid  # Rails uses this for link_to, url_for, etc.
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
```

**Routes:**
```ruby
# config/routes.rb
resources :servers, param: :uuid do
  member do
    post :test_connection
  end
end
```

**Controllers:**
```ruby
def show
  @server = Server.find_by!(uuid: params[:uuid])
end
```

**Why:**
- Security: Prevents resource enumeration
- Privacy: Doesn't reveal database size/state
- Future-proof: Can change ID strategy without breaking URLs

---

### 2. Encrypted Attributes

**Use Rails built-in encryption for sensitive data:**

```ruby
class Server < ApplicationRecord
  encrypts :password, deterministic: false
end

class LinkedAccount < ApplicationRecord
  encrypts :access_token, deterministic: false
  encrypts :refresh_token, deterministic: false
end
```

**Deterministic vs Non-Deterministic:**
- `deterministic: false` (default) - Cannot query/search, more secure
- `deterministic: true` - Can query/search, less secure

**Most cases use `deterministic: false`.**

---

### 3. Validations

**Order of validations:**
1. Presence validations
2. Format validations
3. Numericality validations
4. Length validations
5. Inclusion/exclusion validations
6. Uniqueness validations
7. Custom validations

```ruby
class Deployment < ApplicationRecord
  # Presence
  validates :name, presence: true
  validates :dokku_app_name, presence: true
  validates :uuid, presence: true

  # Format
  validates :dokku_app_name, format: {
    with: /\A[a-z0-9-]+\z/,
    message: "must contain only lowercase letters, numbers, and hyphens"
  }

  # Length
  validates :name, length: { maximum: 100 }
  validates :description, length: { maximum: 1000 }, allow_blank: true

  # Inclusion
  validates :deployment_method, inclusion: {
    in: %w[manual github_repo public_repo],
    allow_blank: true
  }

  # Uniqueness
  validates :uuid, uniqueness: true
  validates :dokku_app_name, uniqueness: true
  validates :name, uniqueness: { scope: :user_id }

  # Custom
  validate :server_must_have_dokku_installed

  private

  def server_must_have_dokku_installed
    return unless server.present?
    unless server.dokku_installed?
      errors.add(:server, "must have Dokku installed")
    end
  end
end
```

---

### 4. Associations

**Order:**
1. `belongs_to`
2. `has_one`
3. `has_many`
4. `has_and_belongs_to_many`

```ruby
class Deployment < ApplicationRecord
  # belongs_to
  belongs_to :server
  belongs_to :user

  # has_one
  has_one :database_configuration, dependent: :destroy

  # has_many
  has_many :domains, dependent: :destroy
  has_many :environment_variables, dependent: :destroy
  has_many :deployment_attempts, dependent: :destroy

  # has_and_belongs_to_many (through join table)
  has_many :deployment_ssh_keys, dependent: :destroy
  has_many :ssh_keys, through: :deployment_ssh_keys
end
```

**Dependent options:**
- `:destroy` - Delete associated records (runs callbacks)
- `:delete_all` - Delete associated records (no callbacks)
- `:nullify` - Set foreign key to NULL
- `:restrict_with_exception` - Raise error if associated records exist

**Default: Use `:destroy` for proper cleanup and callbacks.**

---

### 5. Scopes

**Scopes go after associations, before callbacks:**

```ruby
class Deployment < ApplicationRecord
  belongs_to :server

  # Scopes
  scope :recent, -> { order(created_at: :desc) }
  scope :for_server, ->(server) { where(server: server) }
  scope :deployed, -> { where(deployment_status: 'deployed') }

  before_validation :generate_uuid
end
```

---

### 6. Callbacks

**Order of callbacks:**
1. `before_validation`
2. `after_validation`
3. `before_save`
4. `before_create` / `before_update`
5. `after_create` / `after_update`
6. `after_save`
7. `after_commit`

```ruby
class Deployment < ApplicationRecord
  before_validation :generate_uuid, on: :create
  before_validation :generate_dokku_app_name, on: :create
  before_validation :normalize_dokku_app_name

  after_create :create_dokku_app_async
end
```

**Avoid complex logic in callbacks.** Extract to service objects instead.

---

### 7. Model Method Organization

**Order:**
1. Constants
2. Associations
3. Validations
4. Scopes
5. Callbacks
6. Class methods
7. Public instance methods
8. Private instance methods

```ruby
class Deployment < ApplicationRecord
  # Constants
  ADJECTIVES = %w[ancient brave calm ...].freeze
  NOUNS = %w[butterfly kingdom ...].freeze

  # Associations
  belongs_to :server

  # Validations
  validates :name, presence: true

  # Scopes
  scope :recent, -> { order(created_at: :desc) }

  # Callbacks
  before_validation :generate_uuid, on: :create

  # Class methods
  def self.for_user(user)
    where(user: user)
  end

  # Public instance methods
  def to_param
    uuid
  end

  def can_deploy?
    server&.dokku_installed?
  end

  # Private instance methods
  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end
```

---

## Controller Patterns

### 1. Standard CRUD Actions

**Order:**
```ruby
class DeploymentsController < ApplicationController
  # GET /deployments
  def index
  end

  # GET /deployments/:uuid
  def show
  end

  # GET /deployments/new
  def new
  end

  # POST /deployments
  def create
  end

  # GET /deployments/:uuid/edit
  def edit
  end

  # PATCH/PUT /deployments/:uuid
  def update
  end

  # DELETE /deployments/:uuid
  def destroy
  end

  # Member actions (require :uuid)
  def deploy
  end

  # Collection actions (no :uuid)
  def search
  end

  private

  # Callbacks
  def set_deployment
  end

  # Strong parameters
  def deployment_params
  end
end
```

### 2. Before Actions

**Common patterns:**

```ruby
class DeploymentsController < ApplicationController
  before_action :authenticate_user!  # Devise
  before_action :set_deployment, only: [:show, :edit, :update, :destroy]
  before_action :authorize_deployment, only: [:edit, :update, :destroy]

  private

  def set_deployment
    @deployment = Deployment.find_by!(uuid: params[:uuid])
  end

  def authorize_deployment
    authorize @deployment  # Pundit
  end
end
```

### 3. Include Concerns

**ActivityTrackable:**
```ruby
class ServersController < ApplicationController
  include ActivityTrackable

  def create
    @server = current_user.servers.build(server_params)
    if @server.save
      log_activity("Created server", details: "Server: #{@server.name}")
      redirect_to @server
    else
      render :new, status: :unprocessable_entity
    end
  end
end
```

**Toastable:**
```ruby
class DeploymentsController < ApplicationController
  include Toastable

  def deploy
    DeploymentJob.perform_later(@deployment)
    show_toast(:success, "Deployment started successfully")
    redirect_to @deployment
  end
end
```

### 4. Authorization (Pundit)

**Every action MUST authorize:**

```ruby
def show
  @deployment = Deployment.find_by!(uuid: params[:uuid])
  authorize @deployment  # Calls DeploymentPolicy#show?
end

def update
  @deployment = Deployment.find_by!(uuid: params[:uuid])
  authorize @deployment  # Calls DeploymentPolicy#update?

  if @deployment.update(deployment_params)
    redirect_to @deployment
  else
    render :edit
  end
end
```

**Scoped queries:**
```ruby
def index
  @deployments = policy_scope(Deployment).recent
  # Users see only their deployments
  # Admins see all deployments
end
```

### 5. Strong Parameters

**Always use strong parameters:**

```ruby
private

def deployment_params
  params.require(:deployment).permit(
    :name,
    :description,
    :deployment_method,
    :repository_url,
    :repository_branch
  )
end
```

**Nested attributes:**
```ruby
def server_params
  params.require(:server).permit(
    :name,
    :ip,
    :username,
    :port,
    :password,
    firewall_rules_attributes: [:id, :rule, :_destroy]
  )
end
```

### 6. Response Formats

**Redirect after successful create/update/destroy:**
```ruby
def create
  @server = current_user.servers.build(server_params)
  if @server.save
    redirect_to @server, notice: "Server created successfully"
  else
    render :new, status: :unprocessable_entity
  end
end
```

**Render for failed validations:**
```ruby
def update
  if @server.update(server_params)
    redirect_to @server, notice: "Server updated successfully"
  else
    render :edit, status: :unprocessable_entity
  end
end
```

---

## Service Object Patterns

### 1. Service Structure

```ruby
class SshConnectionService
  def initialize(server)
    @server = server
    @connection_details = server.connection_details
  end

  def test_connection
    result = { success: false, error: nil, output: '' }

    begin
      # Perform operation
      Net::SSH.start(@connection_details[:host],
                     @connection_details[:username],
                     ssh_options) do |ssh|
        result[:output] = ssh.exec!("echo 'test'")
        result[:success] = true
      end
    rescue Net::SSH::AuthenticationFailed => e
      result[:error] = "Authentication failed"
    rescue StandardError => e
      result[:error] = "Operation failed: #{e.message}"
    end

    result
  end

  private

  def ssh_options
    {
      port: @connection_details[:port],
      keys: @connection_details[:keys],
      password: @connection_details[:password],
      timeout: CONNECTION_TIMEOUT
    }
  end
end
```

### 2. Service Return Values

**ALWAYS return a hash with consistent structure:**

```ruby
{
  success: boolean,       # Required
  error: string or nil,   # Required
  output: string,         # Optional, command output
  # ... other operation-specific keys
}
```

**Examples:**
```ruby
# Success
{ success: true, error: nil, output: "Server connected" }

# Failure
{ success: false, error: "Connection timeout", output: "" }

# With additional data
{
  success: true,
  error: nil,
  dokku_version: "0.28.0",
  apps: ["app1", "app2"]
}
```

### 3. When to Use Services

**Use services for:**
- Complex business logic (deployment workflow)
- External API calls (GitHub, OSV)
- SSH operations (Dokku commands)
- Operations that span multiple models

**Don't use services for:**
- Simple CRUD operations (use Active Record)
- View logic (use helpers)
- Background job logic (put in job itself)

---

## Background Job Patterns

### 1. Job Structure

```ruby
class DeploymentJob < ApplicationJob
  queue_as :default

  def perform(deployment)
    # 1. Update model status
    deployment.update!(deployment_status: 'deploying')

    # 2. Broadcast start to ActionCable
    ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", {
      type: 'started',
      message: 'Starting deployment...'
    })

    # 3. Perform work (via service object)
    service = DeploymentService.new(deployment)
    result = service.deploy_from_repository

    # 4. Update final status
    deployment.update!(
      deployment_status: result[:success] ? 'deployed' : 'failed'
    )

    # 5. Broadcast completion
    ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", {
      type: 'completed',
      success: result[:success],
      error: result[:error]
    })
  end
end
```

### 2. Calling Jobs

**Asynchronous (default):**
```ruby
DeploymentJob.perform_later(deployment)
```

**Synchronous (development/testing):**
```ruby
if Rails.env.development?
  DeploymentJob.perform_now(deployment)
else
  DeploymentJob.perform_later(deployment)
end
```

**With delay:**
```ruby
HealthCheckJob.set(wait: 5.minutes).perform_later(deployment)
```

### 3. Error Handling

**Jobs should handle their own errors:**

```ruby
def perform(deployment)
  begin
    # Perform work
  rescue StandardError => e
    Rails.logger.error "Job failed: #{e.message}"
    deployment.update!(status: 'failed', error: e.message)
    ActionCable.server.broadcast("channel", {
      type: 'error',
      message: e.message
    })
  end
end
```

---

## ActionCable Channel Patterns

### 1. Channel Structure

```ruby
class DeploymentLogsChannel < ApplicationCable::Channel
  def subscribed
    deployment = Deployment.find_by(uuid: params[:uuid])
    return reject unless deployment

    # Optional: Check authorization
    # return reject unless current_user&.can_view?(deployment)

    stream_from "deployment_logs_#{deployment.uuid}"
  end

  def unsubscribed
    # Cleanup when channel is closed
    stop_all_streams
  end
end
```

### 2. Broadcasting

**From Jobs/Services:**
```ruby
ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", {
  type: 'data',
  message: sanitize_utf8(log_line),
  timestamp: Time.current.iso8601
})
```

**Message Types:**
- `started` - Operation started
- `data` - Progress update
- `completed` - Operation completed successfully
- `error` - Operation failed
- `status` - Status change

### 3. Client-Side (Stimulus)

**JavaScript subscription:**
```javascript
import consumer from "../channels/consumer"

export default class extends Controller {
  connect() {
    this.subscription = consumer.subscriptions.create(
      { channel: "DeploymentLogsChannel", uuid: this.deploymentUuid },
      {
        received: (data) => {
          this.handleMessage(data)
        }
      }
    )
  }

  disconnect() {
    if (this.subscription) {
      this.subscription.unsubscribe()
    }
  }

  handleMessage(data) {
    switch(data.type) {
      case 'started':
        // ...
        break
      case 'data':
        this.appendLog(data.message)
        break
      case 'completed':
        // ...
        break
    }
  }
}
```

---

## View and Partial Organization

### 1. View Files

**File naming:**
```
app/views/deployments/index.html.erb
app/views/deployments/show.html.erb
app/views/deployments/_deployment.html.erb  # Partial
app/views/deployments/_form.html.erb        # Form partial
```

### 2. Partials

**Use partials for:**
- Repeated components (cards, list items)
- Forms (shared between new/edit)
- Shared UI elements (navbar, footer)

**Naming:** Start with underscore, render without underscore
```erb
<%# _deployment.html.erb %>
<div class="deployment-card">
  <%= deployment.name %>
</div>

<%# index.html.erb %>
<%= render @deployments %>
<%# or %>
<%= render partial: 'deployment', collection: @deployments %>
```

### 3. Shared Partials

**Location:** `app/views/shared/`

```erb
<%# app/views/shared/_navbar.html.erb %>
<nav>...</nav>

<%# app/views/layouts/application.html.erb %>
<%= render 'shared/navbar' %>
```

---

## JavaScript and Stimulus Conventions

### 1. Stimulus Controller Naming

**File:** `app/javascript/controllers/deployment_logs_controller.js`
**HTML:** `data-controller="deployment-logs"`

```javascript
// ✅ CORRECT
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    console.log("DeploymentLogs controller connected")
  }
}
```

### 2. Targets and Actions

```javascript
export default class extends Controller {
  static targets = ["output", "status"]
  static values = { uuid: String }

  connect() {
    this.subscribe()
  }

  // Action methods
  clear(event) {
    this.outputTarget.innerHTML = ""
  }
}
```

```erb
<div data-controller="deployment-logs"
     data-deployment-logs-uuid-value="<%= @deployment.uuid %>">

  <div data-deployment-logs-target="output"></div>

  <button data-action="click->deployment-logs#clear">
    Clear Logs
  </button>
</div>
```

---

## Testing Conventions

### 1. Model Tests

```ruby
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

  test "should validate IP format" do
    server = Server.new(ip: "invalid")
    refute server.valid?
    assert_includes server.errors[:ip], "must be a valid IP address"
  end
end
```

### 2. Controller Tests

```ruby
require "test_helper"

class ServersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
    @server = servers(:one)
  end

  test "should get index" do
    get servers_url
    assert_response :success
  end

  test "should create server" do
    assert_difference("Server.count") do
      post servers_url, params: { server: {
        name: "Test",
        ip: "1.2.3.4",
        username: "dokku",
        port: 22
      } }
    end
    assert_redirected_to server_url(Server.last)
  end
end
```

---

## Code Style and Best Practices

### 1. Ruby Style

**Indentation:** 2 spaces (no tabs)

**String quotes:**
- Single quotes for simple strings: `'hello'`
- Double quotes for interpolation: `"Hello #{name}"`

**Hash syntax:**
- New style when possible: `{ name: 'value' }`
- Old style when keys are not symbols: `{ 'name' => 'value' }`

**Line length:** Max 120 characters (prefer 80-100)

**Method length:** Max 25 lines (prefer 10-15)

### 2. Comments

**Use comments for:**
- Why, not what
- Complex business logic
- Non-obvious decisions
- TODO/FIXME notes

```ruby
# ✅ GOOD - Explains why
# UTF-8 sanitization required because SSH output can contain invalid bytes
clean_output = sanitize_utf8(output)

# ❌ BAD - Explains what (obvious from code)
# Set the name variable to the user's name
name = user.name
```

### 3. Security Best Practices

**NEVER:**
- Commit secrets to git
- Use raw SQL with user input
- Log sensitive data (passwords, tokens)
- Display sensitive data in views (except public keys)
- Use database IDs in URLs

**ALWAYS:**
- Use UUIDs for public routes
- Encrypt sensitive attributes
- Filter sensitive parameters
- Authorize every controller action
- Sanitize SSH output before storing/broadcasting

---

## Summary Checklist

When adding new code, ask yourself:

### Models
- [ ] Does it use UUID routing? (`uuid` column, `to_param`)
- [ ] Are sensitive fields encrypted?
- [ ] Are validations in the correct order?
- [ ] Are associations properly ordered?
- [ ] Are scopes defined before callbacks?

### Controllers
- [ ] Does it authorize actions with Pundit?
- [ ] Does it use strong parameters?
- [ ] Does it include ActivityTrackable for audit logging?
- [ ] Does it use UUID params, not database IDs?
- [ ] Does it redirect after successful create/update/destroy?

### Services
- [ ] Does it return a consistent hash structure?
- [ ] Does it handle all SSH exceptions?
- [ ] Does it use appropriate timeouts?
- [ ] Does it sanitize UTF-8 output?

### Jobs
- [ ] Does it update model status?
- [ ] Does it broadcast to ActionCable channels?
- [ ] Does it handle errors gracefully?
- [ ] Does it use a service object for complex logic?

### Views
- [ ] Are partials used for repeated elements?
- [ ] Are form helpers used correctly?
- [ ] Is Turbo used for dynamic updates?
- [ ] Are Stimulus controllers properly namespaced?

**When in doubt, check existing code for patterns!**

For more details, see:
- `/CLAUDE.md` - Critical patterns and anti-patterns
- `/docs/ARCHITECTURE.md` - System architecture
- `/docs/features/*.md` - Feature-specific patterns
