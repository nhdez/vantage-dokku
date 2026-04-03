# Real-Time Updates (ActionCable)

## Overview

Real-time updates provide live progress feedback to users during long-running operations like deployments, server updates, and command execution. This is powered by **ActionCable** (Rails' WebSocket framework) with **SolidCable** as the backend.

**Key Benefit:** Users see operations progress in real-time without refreshing the page, creating a responsive, modern UX.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Channel Naming Conventions](#channel-naming-conventions)
3. [Broadcasting Patterns](#broadcasting-patterns)
4. [Subscription Lifecycle](#subscription-lifecycle)
5. [Client-Side Handling](#client-side-handling)
6. [SolidCable Configuration](#solidcable-configuration)
7. [Authorization](#authorization)
8. [Message Types](#message-types)
9. [Debugging WebSocket Issues](#debugging-websocket-issues)
10. [Performance Considerations](#performance-considerations)

---

## Architecture

### ActionCable Stack

```
┌─────────────────────────────────────────────────────────┐
│              Browser (WebSocket Client)                 │
│                                                          │
│  JavaScript subscribes to channel:                      │
│  consumer.subscriptions.create(                         │
│    { channel: "DeploymentLogsChannel",                  │
│      deployment_uuid: "abc-123" }                       │
│  )                                                       │
└─────────────────────┬───────────────────────────────────┘
                      │
                      │ WebSocket (WSS)
                      ▼
┌─────────────────────────────────────────────────────────┐
│               Rails Server (Puma)                       │
│                                                          │
│  ActionCable.server.mount('/cable')                     │
│  ├─ Accepts WebSocket connections                       │
│  ├─ Authenticates via cookies/session                   │
│  ├─ Routes to appropriate channel class                 │
│  └─ Manages subscriptions                               │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│         Channel Classes (app/channels/)                 │
│                                                          │
│  DeploymentLogsChannel                                  │
│  ├─ subscribed() - Authorize & stream_from             │
│  └─ unsubscribed() - Cleanup                            │
│                                                          │
│  CommandExecutionChannel                                │
│  UpdateEnvironmentChannel                               │
│  ... (12 total channels)                                │
└─────────────────────┬───────────────────────────────────┘
                      │
                      │ stream_from "channel_name"
                      ▼
┌─────────────────────────────────────────────────────────┐
│           SolidCable (Database Pub/Sub)                 │
│                                                          │
│  PostgreSQL table: solid_cable_messages                 │
│  ├─ Stores messages temporarily                         │
│  ├─ Polls for new messages                              │
│  └─ Delivers to subscribed clients                      │
└─────────────────────┬───────────────────────────────────┘
                      │
                      │ ActionCable.server.broadcast()
                      ▲
┌─────────────────────────────────────────────────────────┐
│      Background Jobs / Controllers / Services           │
│                                                          │
│  DeploymentJob.perform                                  │
│  ActionCable.server.broadcast(                          │
│    "deployment_logs_#{uuid}",                           │
│    { type: 'data', message: 'Building...' }            │
│  )                                                       │
└─────────────────────────────────────────────────────────┘
```

### Message Flow

1. **Browser** subscribes to channel via JavaScript
2. **Rails** authorizes connection and creates subscription
3. **Background job/service** broadcasts message to channel
4. **SolidCable** stores message in PostgreSQL
5. **ActionCable** polls database for new messages
6. **Browser** receives message via WebSocket
7. **JavaScript** handles message (update UI)

---

## Channel Naming Conventions

### Channel Classes

**Pattern:** `{Operation}Channel`

**Examples:**
- `DeploymentLogsChannel` - Deployment progress logs
- `CommandExecutionChannel` - Real-time command output
- `UpdateEnvironmentChannel` - Environment variable sync
- `UpdateDomainsChannel` - Domain/SSL configuration
- `InstallDokkuChannel` - Dokku installation progress
- `ServerLogsChannel` - Server command logs

**File location:** `/app/channels/{operation}_channel.rb`

### Stream Names

**Pattern:** `{operation}_{resource_uuid}`

**Examples:**
```ruby
"deployment_logs_550e8400-e29b-41d4-a716-446655440000"
"command_execution_550e8400-e29b-41d4-a716-446655440000"
"update_environment_550e8400-e29b-41d4-a716-446655440000"
"server_logs_8b7d4c1a-2f3e-4d6a-9c8b-5e1f7a9d3c2b"
```

**Why UUIDs in stream names:**
- Unique per resource (no collisions)
- Secure (can't guess other streams)
- Works with UUID routing pattern

---

## Broadcasting Patterns

### Standard Broadcasting Pattern

**Used in background jobs and services:**

```ruby
# 1. Broadcast start
ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", {
  type: 'started',
  message: 'Starting deployment...',
  timestamp: Time.current.iso8601
})

# 2. Broadcast progress updates
logs.each_line do |line|
  ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", {
    type: 'data',
    message: sanitize_utf8(line),
    timestamp: Time.current.iso8601
  })
end

# 3. Broadcast completion
ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", {
  type: 'completed',
  success: true,
  message: 'Deployment completed successfully!',
  timestamp: Time.current.iso8601
})

# Or broadcast error
ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", {
  type: 'error',
  message: 'Deployment failed: Connection timeout',
  timestamp: Time.current.iso8601
})
```

### Streaming SSH Output

**Real-time SSH command output:**

```ruby
# app/services/ssh_connection_service.rb
def execute_command_with_streaming(ssh, command, deployment_uuid)
  ssh.exec!(command) do |channel, stream, data|
    # CRITICAL: Sanitize UTF-8 before broadcasting
    clean_data = sanitize_utf8(data)

    ActionCable.server.broadcast("deployment_logs_#{deployment_uuid}", {
      type: 'data',
      stream: stream.to_s,  # 'stdout' or 'stderr'
      message: clean_data,
      timestamp: Time.current.iso8601
    })
  end
end
```

**User sees each line of output as it's generated on the server!**

### Status Updates

**Update UI elements without full logs:**

```ruby
# Update status badge
ActionCable.server.broadcast("deployment_status_#{deployment.uuid}", {
  type: 'status_change',
  status: 'deploying',
  status_text: 'Deploying',
  status_class: 'bg-warning text-dark'
})

# Update progress bar
ActionCable.server.broadcast("deployment_status_#{deployment.uuid}", {
  type: 'progress',
  percentage: 75,
  message: 'Step 3 of 4: Verifying deployment'
})
```

### Batch Broadcasting

**For multiple related updates:**

```ruby
# Broadcast multiple environment variables at once
env_vars.each do |var|
  updates << {
    key: var.key,
    value: var.value,
    source: var.source
  }
end

ActionCable.server.broadcast("update_environment_#{deployment.uuid}", {
  type: 'bulk_update',
  variables: updates,
  count: updates.size
})
```

---

## Subscription Lifecycle

### Channel Class Structure

```ruby
# app/channels/deployment_logs_channel.rb
class DeploymentLogsChannel < ApplicationCable::Channel
  def subscribed
    # Called when client subscribes to channel
    deployment_uuid = params[:deployment_uuid]

    if deployment_uuid.present?
      # Create stream subscription
      stream_from "deployment_logs_#{deployment_uuid}"

      Rails.logger.info "DeploymentLogsChannel: User #{current_user&.id} subscribed to #{deployment_uuid}"
    else
      # Reject subscription if missing required params
      reject
    end
  end

  def unsubscribed
    # Called when client unsubscribes (closes tab, navigates away, etc.)
    Rails.logger.info "DeploymentLogsChannel: Unsubscribed"

    # Cleanup if needed (usually automatic)
    stop_all_streams
  end

  # Optional: Custom actions callable from client
  def start_logging(data)
    # Client can call: subscription.perform('start_logging', { level: 'debug' })
  end
end
```

### Multiple Streams Per Channel

**Subscribe to multiple related streams:**

```ruby
class DeploymentLogsChannel < ApplicationCable::Channel
  def subscribed
    deployment_uuid = params[:deployment_uuid]
    attempt_id = params[:attempt_id]

    # Subscribe to general deployment logs
    if deployment_uuid.present?
      stream_from "deployment_logs_#{deployment_uuid}"
    end

    # Also subscribe to specific attempt logs
    if attempt_id.present?
      stream_from "deployment_attempt_logs_#{attempt_id}"
    end
  end
end
```

**Benefits:**
- Get logs for current deployment
- Also get logs for specific attempt
- Flexible subscription based on params

---

## Client-Side Handling

### JavaScript Subscription (Stimulus)

**Basic subscription:**

```javascript
// app/javascript/controllers/deployment_logs_controller.js
import { Controller } from "@hotwired/stimulus"
import consumer from "../channels/consumer"

export default class extends Controller {
  static targets = ["output", "status"]
  static values = {
    deploymentUuid: String,
    attemptId: String
  }

  connect() {
    this.subscribe()
  }

  disconnect() {
    this.unsubscribe()
  }

  subscribe() {
    this.subscription = consumer.subscriptions.create(
      {
        channel: "DeploymentLogsChannel",
        deployment_uuid: this.deploymentUuidValue,
        attempt_id: this.attemptIdValue
      },
      {
        connected: () => {
          console.log("Connected to DeploymentLogsChannel")
        },

        disconnected: () => {
          console.log("Disconnected from DeploymentLogsChannel")
        },

        received: (data) => {
          this.handleMessage(data)
        }
      }
    )
  }

  unsubscribe() {
    if (this.subscription) {
      this.subscription.unsubscribe()
      this.subscription = null
    }
  }

  handleMessage(data) {
    switch(data.type) {
      case 'started':
        this.handleStarted(data)
        break
      case 'data':
        this.appendLog(data.message)
        break
      case 'completed':
        this.handleCompleted(data)
        break
      case 'error':
        this.handleError(data)
        break
      default:
        console.log("Unknown message type:", data.type)
    }
  }

  handleStarted(data) {
    this.statusTarget.textContent = "Deploying..."
    this.statusTarget.className = "badge bg-warning text-dark"
  }

  appendLog(message) {
    const line = document.createElement('div')
    line.textContent = message
    this.outputTarget.appendChild(line)

    // Auto-scroll to bottom
    this.outputTarget.scrollTop = this.outputTarget.scrollHeight
  }

  handleCompleted(data) {
    if (data.success) {
      this.statusTarget.textContent = "Deployed"
      this.statusTarget.className = "badge bg-success"
    } else {
      this.statusTarget.textContent = "Failed"
      this.statusTarget.className = "badge bg-danger"
    }
  }

  handleError(data) {
    this.appendLog(`ERROR: ${data.message}`)
    this.statusTarget.textContent = "Failed"
    this.statusTarget.className = "badge bg-danger"
  }
}
```

### HTML Integration

```erb
<%# app/views/deployments/show.html.erb %>
<div data-controller="deployment-logs"
     data-deployment-logs-deployment-uuid-value="<%= @deployment.uuid %>"
     data-deployment-logs-attempt-id-value="<%= @deployment_attempt&.id %>">

  <div class="card">
    <div class="card-header d-flex justify-content-between align-items-center">
      <h5>Deployment Logs</h5>
      <span data-deployment-logs-target="status" class="badge bg-secondary">
        Pending
      </span>
    </div>

    <div class="card-body">
      <div data-deployment-logs-target="output"
           class="log-output"
           style="height: 400px; overflow-y: auto; font-family: monospace; background: #1e1e1e; color: #d4d4d4; padding: 1rem;">
        <!-- Logs appear here in real-time -->
      </div>
    </div>
  </div>
</div>
```

### Calling Server-Side Actions

**Client can trigger server-side channel methods:**

```javascript
// JavaScript
this.subscription.perform('start_logging', { level: 'debug' })

// Ruby (in channel)
class DeploymentLogsChannel < ApplicationCable::Channel
  def start_logging(data)
    level = data['level'] || 'info'
    # Perform server-side action
    Rails.logger.info "Starting logging at level: #{level}"
  end
end
```

---

## SolidCable Configuration

### Why SolidCable?

**Traditional ActionCable:** Requires Redis for pub/sub
**SolidCable:** Uses PostgreSQL for pub/sub

**Benefits:**
- ✅ No Redis dependency
- ✅ One less service to manage
- ✅ Persistent message storage
- ✅ Works with multiple web server processes
- ✅ Simpler deployment

**Trade-offs:**
- ❌ Higher database load (frequent polling)
- ❌ May not scale as well as Redis for very high message volumes
- ✅ Acceptable for moderate traffic (1,000-10,000 req/day)

### Configuration

**config/cable.yml:**
```yaml
development:
  adapter: async  # In-memory (single process)

test:
  adapter: test   # Test adapter

production:
  adapter: solid_cable
  connects_to:
    database:
      writing: cable  # Uses cable database
```

**Database setup:**
```ruby
# config/database.yml
production:
  primary:
    adapter: postgresql
    database: vantage_production

  cable:
    adapter: postgresql
    database: vantage_production
    migrations_paths: db/cable_migrate
```

**Same PostgreSQL instance, different schema for cable tables.**

### Cable Tables

**Generated by SolidCable:**
```sql
solid_cable_messages (
  id bigint,
  channel text,
  payload text,
  created_at timestamp
)
```

**Automatic cleanup:**
- Old messages deleted after delivery
- Stale connections purged
- No manual maintenance needed

### Application Configuration

**config/environments/production.rb:**
```ruby
# Mount ActionCable
config.action_cable.mount_path = '/cable'

# URL for WebSocket connections
config.action_cable.url = "wss://#{ENV['APP_HOST']}/cable"

# Allowed request origins
config.action_cable.allowed_request_origins = [
  "https://#{ENV['APP_HOST']}",
  "http://#{ENV['APP_HOST']}"
]

# Disable request origin check in development
config.action_cable.disable_request_forgery_protection = false
```

**routes.rb:**
```ruby
Rails.application.routes.draw do
  mount ActionCable.server => '/cable'
  # ... other routes
end
```

---

## Authorization

### Current User in Channels

**ActionCable has access to current_user:**

```ruby
# app/channels/application_cable/connection.rb
module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

    def find_verified_user
      # Authenticate via cookies/session
      if verified_user = env['warden'].user
        verified_user
      else
        reject_unauthorized_connection
      end
    end
  end
end
```

### Authorizing Subscriptions

**Check user has access to resource:**

```ruby
class CommandExecutionChannel < ApplicationCable::Channel
  def subscribed
    deployment_uuid = params[:deployment_uuid]

    # Verify user owns this deployment
    deployment = current_user.deployments.find_by(uuid: deployment_uuid)

    if deployment
      stream_from "command_execution_#{deployment_uuid}"
    else
      Rails.logger.warn "Unauthorized access attempt: User #{current_user.id} -> Deployment #{deployment_uuid}"
      reject  # Reject subscription
    end
  end
end
```

**Benefits:**
- Users can't subscribe to other users' streams
- Authorization at subscription time
- Logged attempts for security audits

### Admin Channels

**Admin-only channels:**

```ruby
class AdminDashboardChannel < ApplicationCable::Channel
  def subscribed
    unless current_user&.has_role?(:admin)
      Rails.logger.warn "Non-admin subscription attempt: User #{current_user&.id}"
      reject
      return
    end

    stream_from "admin_dashboard"
  end
end
```

---

## Message Types

### Standard Message Types

**Convention:** Use `type` field to indicate message purpose

```ruby
# Started
{ type: 'started', message: 'Operation starting...' }

# Progress data
{ type: 'data', message: 'Log line here', stream: 'stdout' }

# Status update
{ type: 'status', status: 'deploying', percentage: 50 }

# Completion
{ type: 'completed', success: true, message: 'Done!' }

# Error
{ type: 'error', message: 'Failed: timeout', error_code: 'TIMEOUT' }

# Custom
{ type: 'custom_event', data: { ... } }
```

### Message Structure Best Practices

**Always include:**
- `type` - Message type (started, data, completed, error)
- `message` - Human-readable message
- `timestamp` - ISO8601 timestamp (optional but recommended)

**Optional fields:**
- `success` - Boolean (for completion messages)
- `error_code` - Machine-readable error code
- `stream` - stdout/stderr (for SSH output)
- `percentage` - Progress percentage
- `data` - Additional structured data

**Example:**
```ruby
ActionCable.server.broadcast("deployment_logs_#{uuid}", {
  type: 'data',
  message: sanitize_utf8(line),
  stream: 'stdout',
  timestamp: Time.current.iso8601,
  line_number: line_count
})
```

---

## Debugging WebSocket Issues

### Issue 1: WebSocket Not Connecting

**Symptoms:**
- Console shows "WebSocket connection failed"
- No real-time updates

**Check:**

1. **ActionCable mounted?**
   ```ruby
   # config/routes.rb
   mount ActionCable.server => '/cable'
   ```

2. **Correct URL configured?**
   ```ruby
   # config/environments/production.rb
   config.action_cable.url = "wss://#{ENV['APP_HOST']}/cable"
   ```

3. **APP_HOST env variable set?**
   ```bash
   echo $APP_HOST  # Should be your domain
   ```

4. **Browser dev tools:**
   - Open Network tab → WS filter
   - Look for `/cable` connection
   - Check status (should be 101 Switching Protocols)

5. **Server logs:**
   ```bash
   tail -f log/production.log | grep ActionCable
   # Should see: "Started GET "/cable""
   ```

### Issue 2: Subscriptions Rejected

**Symptoms:**
- Subscription created but no messages received
- "Subscription rejected" in logs

**Check:**

1. **Authorization failing?**
   ```ruby
   # Check channel logs
   Rails.logger.warn "Unauthorized access attempt..."
   ```

2. **Missing parameters?**
   ```javascript
   // Must pass required params
   { channel: "DeploymentLogsChannel", deployment_uuid: uuid }
   ```

3. **Current user nil?**
   ```ruby
   # In channel
   Rails.logger.info "Current user: #{current_user&.id}"
   ```

### Issue 3: Messages Not Broadcasting

**Symptoms:**
- Subscription successful
- No messages received
- Server logs show broadcasts

**Check:**

1. **Correct stream name?**
   ```ruby
   # Broadcasting
   ActionCable.server.broadcast("deployment_logs_#{uuid}", data)

   # Subscribing
   stream_from "deployment_logs_#{uuid}"  # Must match!
   ```

2. **Worker process running?**
   ```bash
   # SolidCable requires worker for polling
   ps aux | grep solid_queue
   ```

3. **Cable database configured?**
   ```yaml
   # config/database.yml
   production:
     cable:
       adapter: postgresql
       database: vantage_production
   ```

4. **Check solid_cable_messages table:**
   ```sql
   SELECT * FROM solid_cable_messages ORDER BY created_at DESC LIMIT 10;
   ```

### Issue 4: Messages Delayed

**Symptoms:**
- Messages arrive 5-30 seconds late
- Polling interval too long

**Check:**

1. **SolidCable poll interval:**
   ```ruby
   # Decrease poll interval (default: 1s)
   # Not directly configurable, but check worker is running
   ```

2. **Database performance:**
   ```sql
   -- Check slow queries
   SELECT * FROM pg_stat_statements WHERE query LIKE '%solid_cable%';
   ```

3. **Worker load:**
   - Too many background jobs?
   - Worker process overloaded?

### Issue 5: Connection Drops

**Symptoms:**
- WebSocket connects, then disconnects
- Frequent reconnections

**Check:**

1. **Keepalive settings:**
   ```ruby
   # config/cable.yml - SolidCable handles this automatically
   ```

2. **Load balancer timeout:**
   - Ensure LB allows long-lived WebSocket connections
   - Increase idle timeout (e.g., 60 minutes)

3. **Server restart:**
   - Deployments kill WebSocket connections
   - Clients should auto-reconnect

### Debugging Tools

**Browser console:**
```javascript
// Check subscription status
App.cable.subscriptions.subscriptions
// => [Subscription, Subscription, ...]

// Manually subscribe
subscription = App.cable.subscriptions.create(
  { channel: "DeploymentLogsChannel", deployment_uuid: "abc-123" },
  { received: (data) => console.log(data) }
)

// Unsubscribe
subscription.unsubscribe()
```

**Rails console:**
```ruby
# Manually broadcast
ActionCable.server.broadcast("deployment_logs_abc-123", {
  type: 'test',
  message: 'Manual test message'
})

# Check active connections
ActionCable.server.connections.size

# Check subscriptions (not easily accessible)
```

---

## Performance Considerations

### Message Size

**Keep messages small:**

```ruby
# ❌ BAD - Large messages
ActionCable.server.broadcast(channel, {
  type: 'data',
  message: huge_log_string,  # 10 MB of logs!
  deployment: deployment.as_json(include: :everything)
})

# ✅ GOOD - Small messages
logs.each_line do |line|
  ActionCable.server.broadcast(channel, {
    type: 'data',
    message: line  # One line at a time
  })
end
```

**Why:**
- Faster transmission
- Less memory usage
- Better UI responsiveness
- Easier to process on client

### Message Frequency

**Avoid message spam:**

```ruby
# ❌ BAD - Too frequent
1000.times do |i|
  ActionCable.server.broadcast(channel, { percentage: i / 10.0 })
end

# ✅ GOOD - Throttled
last_broadcast = Time.current
output.each_line do |line|
  ActionCable.server.broadcast(channel, { type: 'data', message: line })

  # Broadcast status every 2 seconds
  if Time.current - last_broadcast > 2
    ActionCable.server.broadcast(channel, {
      type: 'status',
      percentage: calculate_progress
    })
    last_broadcast = Time.current
  end
end
```

### Connection Limits

**Current limits (Rails default):**
- Worker process handles WebSocket connections
- Puma thread pool size matters
- SolidCable polls database frequently

**Scaling:**
```ruby
# config/puma.rb
workers ENV.fetch("WEB_CONCURRENCY") { 2 }
threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 }
threads threads_count, threads_count

# Each worker can handle ~5 WebSocket connections
# 2 workers × 5 threads = ~10 concurrent WebSocket connections
```

### Database Load

**SolidCable queries:**
- Inserts message for each broadcast
- Polls for new messages every ~1 second
- Deletes delivered messages

**Mitigation:**
- Index on `created_at` column (auto-created)
- Auto-vacuum configured
- Connection pooling

**For very high traffic:**
- Consider Redis adapter instead
- Or increase database resources

---

## Summary

### Key Takeaways

1. **ActionCable provides real-time updates** via WebSockets
2. **SolidCable uses PostgreSQL** instead of Redis (simpler deployment)
3. **Channel naming:** `{Operation}Channel` (e.g., `DeploymentLogsChannel`)
4. **Stream naming:** `{operation}_{resource_uuid}`
5. **Always sanitize UTF-8** before broadcasting SSH output
6. **Message types:** started, data, completed, error
7. **Authorization:** Check user has access in `subscribed` method
8. **Debugging:** Check browser Network tab (WS filter), server logs, worker process

### Checklist for New Channels

When adding new ActionCable channels:

- [ ] Create channel class in `/app/channels/`
- [ ] Implement `subscribed` and `unsubscribed` methods
- [ ] Authorize subscription (verify user has access)
- [ ] Use unique stream name with UUID
- [ ] Broadcast with consistent message structure (type, message, timestamp)
- [ ] Sanitize UTF-8 output if from SSH
- [ ] Create JavaScript/Stimulus controller for client-side
- [ ] Handle all message types (started, data, completed, error)
- [ ] Test WebSocket connection in browser dev tools
- [ ] Log subscription/unsubscription for debugging

### Related Documentation

- [CLAUDE.md](/CLAUDE.md) - ActionCable broadcasting patterns
- [ARCHITECTURE.md](/docs/ARCHITECTURE.md) - Real-time communication architecture
- [ssh-integration.md](/docs/features/ssh-integration.md) - UTF-8 sanitization
- [deployment-system.md](/docs/features/deployment-system.md) - Deployment progress streaming

---

**Real-time updates are a key differentiator of Vantage-Dokku. Use them wisely!**
