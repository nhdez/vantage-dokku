# SSH Integration

## Overview

SSH integration is the **most critical and complex component** of Vantage-Dokku. All communication with remote Dokku servers happens through SSH connections, making this the foundation of the entire application.

**Location:** `/app/services/ssh_connection_service.rb` (2,831 lines)

**Purpose:** Execute Dokku CLI commands on remote servers via SSH, manage server configurations, handle deployments, and stream real-time output.

---

## Table of Contents

1. [Architecture](#architecture)
2. [Connection Lifecycle](#connection-lifecycle)
3. [Timeout Strategy](#timeout-strategy)
4. [Authentication Methods](#authentication-methods)
5. [Error Handling](#error-handling)
6. [UTF-8 Encoding Issues](#utf-8-encoding-issues)
7. [Command Execution Patterns](#command-execution-patterns)
8. [Key Operations](#key-operations)
9. [Performance Considerations](#performance-considerations)
10. [Testing SSH Operations](#testing-ssh-operations)
11. [Common Issues and Solutions](#common-issues-and-solutions)

---

## Architecture

### SshConnectionService Design

```
┌─────────────────────────────────────────────────────────┐
│              SshConnectionService                       │
│                                                          │
│  Public Methods (50+ operations):                       │
│  ├─ install_dokku_with_key_setup                       │
│  ├─ test_connection                                     │
│  ├─ create_dokku_app                                    │
│  ├─ destroy_dokku_app                                   │
│  ├─ sync_dokku_environment_variables                    │
│  ├─ sync_dokku_domains                                  │
│  ├─ enable_letsencrypt                                  │
│  ├─ configure_database                                  │
│  ├─ sync_port_mappings                                  │
│  └─ ... (40+ more operations)                           │
│                                                          │
│  Private Helper Methods:                                │
│  ├─ ssh_options (connection configuration)             │
│  ├─ execute_command (single command execution)         │
│  ├─ execute_command_with_streaming (real-time output) │
│  ├─ sanitize_utf8 (encoding cleanup)                   │
│  └─ perform_* (operation-specific logic)               │
└─────────────────────────────────────────────────────────┘
                          │
                          │ Net::SSH.start
                          ▼
┌─────────────────────────────────────────────────────────┐
│               Remote Dokku Server                       │
│                                                          │
│  SSH Daemon (port 22 or custom)                         │
│  ├─ Authenticates via SSH key or password              │
│  ├─ Executes commands as specified user                │
│  └─ Returns stdout/stderr                              │
│                                                          │
│  Dokku CLI:                                             │
│  ├─ dokku apps:create myapp                            │
│  ├─ dokku config:set myapp KEY=value                   │
│  ├─ dokku domains:add myapp example.com                │
│  └─ ... (100+ Dokku commands)                          │
└─────────────────────────────────────────────────────────┘
```

### Initialization

```ruby
class SshConnectionService
  def initialize(server)
    @server = server
    @connection_details = server.connection_details
    # @connection_details contains:
    # - :host (IP address)
    # - :username
    # - :port
    # - :keys (SSH key paths)
    # - :password (optional fallback)
  end
end
```

**Usage:**
```ruby
server = Server.find_by(uuid: params[:uuid])
service = SshConnectionService.new(server)
result = service.test_connection
```

---

## Connection Lifecycle

### 1. Connection Establishment

```ruby
Net::SSH.start(
  @connection_details[:host],      # Server IP
  @connection_details[:username],  # SSH username (usually 'dokku' or 'root')
  ssh_options                      # Authentication + timeout config
) do |ssh|
  # Execute commands within this block
  # Connection automatically closed when block exits
end
```

### 2. Connection Flow

```
┌─────────────────────────────────────────────────────────┐
│ 1. Get Connection Details                              │
│    ├─ Server IP, username, port                        │
│    ├─ SSH keys (ENV var or AppSetting)                 │
│    └─ Password (optional fallback)                     │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│ 2. Establish SSH Connection                            │
│    ├─ Connect to server:port                           │
│    ├─ Try SSH key authentication first                 │
│    ├─ Fallback to password if key fails                │
│    └─ Timeout after CONNECTION_TIMEOUT (10s)           │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│ 3. Execute Command(s)                                  │
│    ├─ Run Dokku commands (sudo dokku ...)             │
│    ├─ Stream output for long operations                │
│    └─ Timeout based on operation type                  │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│ 4. Handle Response                                     │
│    ├─ Sanitize UTF-8 encoding                         │
│    ├─ Parse output for success/failure                 │
│    └─ Extract relevant information                     │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│ 5. Update Server Metadata                             │
│    ├─ last_connected_at = Time.current                │
│    ├─ connection_status = 'connected'                  │
│    └─ Optional: dokku_version, system_info             │
└─────────────────────┬───────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────┐
│ 6. Close Connection                                    │
│    └─ Automatic when Net::SSH.start block exits       │
└─────────────────────────────────────────────────────────┘
```

### 3. SSH Options Configuration

```ruby
private

def ssh_options
  options = {
    port: @connection_details[:port],
    timeout: CONNECTION_TIMEOUT,
    non_interactive: true,
    verify_host_key: :never,  # Skip host key verification
    keepalive: true,
    keepalive_interval: 60
  }

  # SSH key authentication (preferred)
  if @connection_details[:keys]&.any?
    options[:keys] = @connection_details[:keys]
    options[:keys_only] = false  # Allow password fallback
  end

  # Password authentication (fallback)
  if @connection_details[:password].present?
    options[:password] = @connection_details[:password]
  end

  options
end
```

**Key Options:**
- `verify_host_key: :never` - Skip host key verification (reduces friction)
- `non_interactive: true` - Never prompt for input
- `keys_only: false` - Try SSH key first, then password
- `keepalive: true` - Keep connection alive during long operations

---

## Timeout Strategy

### Timeout Constants

Different operations require different timeout durations:

```ruby
# File: app/services/ssh_connection_service.rb

CONNECTION_TIMEOUT = 10    # seconds - Initial SSH connection
COMMAND_TIMEOUT = 30       # seconds - Standard Dokku commands
UPDATE_TIMEOUT = 600       # seconds (10 minutes) - Server updates
INSTALL_TIMEOUT = 900      # seconds (15 minutes) - Dokku installation
DOMAIN_TIMEOUT = 600       # seconds (10 minutes) - Domain/SSL operations
ENV_TIMEOUT = 180          # seconds (3 minutes) - Environment variables
```

### Timeout Usage by Operation

| Operation | Timeout | Reason |
|-----------|---------|--------|
| **Connection test** | 10s | Quick check, should be fast |
| **App creation** | 10s | Simple `dokku apps:create` |
| **App deletion** | 30s | May need to stop containers |
| **Environment sync** | 3min | Many variables = slow |
| **Domain configuration** | 10min | DNS propagation checks |
| **SSL certificate** | 10min | Let's Encrypt verification |
| **Server update** | 10min | `apt-get update/upgrade` |
| **Dokku installation** | 15min | Bootstrap script download |
| **Database creation** | 30s | Plugin commands |
| **Port mapping** | 30s | Quick nginx reconfiguration |

### Why Different Timeouts?

**Short timeouts (10-30s):**
- Prevent hanging on dead servers
- Fast feedback for users
- Most Dokku commands are quick

**Medium timeouts (3-10min):**
- Domain/SSL operations involve external services
- Environment variable syncs with many vars
- Server updates download packages

**Long timeouts (15min):**
- Dokku installation downloads ~100MB+ files
- May compile native extensions
- First-time setup always slow

### Timeout Pattern

```ruby
def some_operation
  result = { success: false, error: nil }

  begin
    Timeout::timeout(APPROPRIATE_TIMEOUT) do
      Net::SSH.start(...) do |ssh|
        # Perform operation
        result[:success] = true
      end
    end
  rescue Timeout::Error => e
    result[:error] = "Operation timeout. Try increasing timeout or check server performance."
  end

  result
end
```

---

## Authentication Methods

### 1. SSH Key Authentication (Preferred)

**Why preferred:**
- More secure than passwords
- No password stored/transmitted
- Required for automated deployments
- Can use multiple keys

**Key Sources (in priority order):**

```ruby
def ssh_key_paths
  paths = []

  # 1. Environment variable (highest priority)
  if ENV['DOKKU_SSH_KEY_PATH'].present?
    paths << ENV['DOKKU_SSH_KEY_PATH']
  else
    # 2. Database AppSetting (fallback)
    ssh_key_path = AppSetting.get('dokku_ssh_key_path')
    private_key_content = AppSetting.get('dokku_ssh_private_key')

    if ssh_key_path.present? && private_key_content.present?
      # Create temporary key file
      key_file_path = create_temp_ssh_key_file(ssh_key_path, private_key_content)
      paths << key_file_path if key_file_path
    end
  end

  paths.compact
end
```

**Temporary Key File Creation:**

```ruby
def create_temp_ssh_key_file(key_path, private_key_content)
  return nil if private_key_content.blank?

  # Ensure directory exists
  key_dir = File.dirname(key_path)
  FileUtils.mkdir_p(key_dir) unless File.directory?(key_dir)

  # Write private key
  File.write(key_path, private_key_content)

  # CRITICAL: Set correct permissions (0600 = -rw-------)
  # SSH will refuse to use keys with incorrect permissions
  File.chmod(0600, key_path)

  key_path
rescue => e
  Rails.logger.error "Failed to create SSH key file: #{e.message}"
  nil
end
```

**Security Note:** Private keys MUST have 0600 permissions (owner read/write only).

### 2. Password Authentication (Fallback)

**When to use:**
- Initial server setup
- SSH key setup failed
- Emergency access

**How it works:**

```ruby
# Server model
encrypts :password, deterministic: false  # Encrypted in database

def connection_details
  details = {
    host: ip,
    username: username,
    port: port,
    keys: ssh_key_paths
  }

  # Add password as fallback
  details[:password] = password if password.present?

  details
end
```

**Net::SSH behavior:**
- Tries SSH keys first (`keys_only: false`)
- Falls back to password if key authentication fails
- No manual retry logic needed

---

## Error Handling

### Required Exception Handling

**EVERY SSH operation MUST handle these exceptions:**

```ruby
def some_ssh_operation
  result = { success: false, error: nil, output: '' }

  begin
    Timeout::timeout(COMMAND_TIMEOUT) do
      Net::SSH.start(...) do |ssh|
        # Perform operation
        result[:success] = true
      end
    end

  # Authentication failures
  rescue Net::SSH::AuthenticationFailed => e
    result[:error] = "Authentication failed. Please check your SSH key or password."

  # Connection timeouts
  rescue Net::SSH::ConnectionTimeout, Timeout::Error => e
    result[:error] = "Connection timeout. Server may be unreachable."

  # Connection refused (SSH service not running)
  rescue Errno::ECONNREFUSED => e
    result[:error] = "Connection refused. Check if SSH service is running on port #{@connection_details[:port]}."

  # Host unreachable (network issue)
  rescue Errno::EHOSTUNREACH => e
    result[:error] = "Host unreachable. Check the IP address and network connectivity."

  # Catch-all for unexpected errors
  rescue StandardError => e
    result[:error] = "Operation failed: #{e.message}"
    Rails.logger.error "SSH operation error: #{e.class} - #{e.message}\n#{e.backtrace.join("\n")}"
  end

  result
end
```

### Error Messages - User-Friendly

**Good error messages:**
- ✅ "Authentication failed. Please check your SSH key or password."
- ✅ "Connection timeout. Server may be unreachable."
- ✅ "Connection refused. Check if SSH service is running on port 22."

**Bad error messages:**
- ❌ "Net::SSH::AuthenticationFailed"
- ❌ "Errno::ECONNREFUSED"
- ❌ "Error occurred"

### Error Logging

```ruby
rescue StandardError => e
  error_msg = "SSH operation failed: #{e.message}"
  Rails.logger.error "#{error_msg}\n#{e.backtrace.join("\n")}"
  result[:error] = error_msg
end
```

**Always log:**
- Exception class and message
- Backtrace for debugging
- Server details (IP, username)
- Operation being performed

---

## UTF-8 Encoding Issues

### The Problem

**SSH output can contain invalid UTF-8 bytes:**
- Docker build logs with binary data
- Linux kernel messages
- Non-English error messages
- ANSI color codes
- Control characters

**What happens without sanitization:**
```ruby
# ❌ THIS WILL CRASH
ssh_output = ssh.exec!("dokku ps:rebuild myapp")  # Contains invalid UTF-8
ActionCable.server.broadcast("channel", { data: ssh_output })
# => ArgumentError: invalid byte sequence in UTF-8
```

### The Solution

**ALWAYS sanitize SSH output before storing/broadcasting:**

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
      replace: '?')        # Use '?' as replacement character
  end

  clean_text
end
```

### Where to Apply Sanitization

```ruby
# ✅ CORRECT - Before broadcasting
output = ssh.exec!("dokku apps:list")
clean_output = sanitize_utf8(output)
ActionCable.server.broadcast("channel", { data: clean_output })

# ✅ CORRECT - Before storing in database
deployment_attempt.update!(
  logs: sanitize_utf8(logs.join("\n"))
)

# ✅ CORRECT - During streaming
ssh.exec!("dokku ps:rebuild myapp") do |channel, stream, data|
  clean_data = sanitize_utf8(data)
  ActionCable.server.broadcast("logs_#{uuid}", {
    type: 'data',
    message: clean_data
  })
end
```

### Real-World Example

**Docker build output (common source of invalid UTF-8):**
```
Step 1/10 : FROM ruby:3.4
 ---> a1b2c3d4e5f6
Step 2/10 : RUN apt-get update
 ---> Running in xyz123
\x1b[91mE: Failed to fetch...\x1b[0m  ← Invalid UTF-8 + ANSI codes
```

**After sanitization:**
```
Step 1/10 : FROM ruby:3.4
 ---> a1b2c3d4e5f6
Step 2/10 : RUN apt-get update
 ---> Running in xyz123
?[91mE: Failed to fetch...?[0m  ← Valid UTF-8
```

---

## Command Execution Patterns

### 1. Simple Command Execution

**For commands with short output:**

```ruby
def execute_command(ssh, command)
  output = ssh.exec!(command)
  sanitize_utf8(output)
rescue => e
  Rails.logger.error "Command failed: #{command} - #{e.message}"
  nil
end
```

**Usage:**
```ruby
Net::SSH.start(...) do |ssh|
  apps = execute_command(ssh, "sudo dokku apps:list")
  version = execute_command(ssh, "dokku version")
  # etc.
end
```

### 2. Streaming Command Execution

**For long-running commands with real-time output:**

```ruby
def execute_command_with_streaming(ssh, command, channel_name)
  ssh.exec!(command) do |channel, stream, data|
    # Sanitize UTF-8 before broadcasting
    clean_data = sanitize_utf8(data)

    # Broadcast to ActionCable
    ActionCable.server.broadcast(channel_name, {
      type: 'data',
      stream: stream.to_s,  # :stdout or :stderr
      message: clean_data
    })
  end
end
```

**Usage:**
```ruby
Net::SSH.start(...) do |ssh|
  execute_command_with_streaming(
    ssh,
    "sudo dokku ps:rebuild myapp",
    "deployment_logs_#{deployment.uuid}"
  )
end
```

**User sees real-time output in browser as command executes!**

### 3. Multi-Command Sequences

**For operations requiring multiple commands:**

```ruby
def configure_database(app_name, db_type, db_name)
  result = { success: false, error: nil, output: '' }

  begin
    Timeout::timeout(COMMAND_TIMEOUT) do
      Net::SSH.start(...) do |ssh|
        output = []

        # Step 1: Create database
        output << execute_command(ssh, "sudo dokku #{db_type}:create #{db_name}")

        # Step 2: Link to app
        output << execute_command(ssh, "sudo dokku #{db_type}:link #{db_name} #{app_name}")

        # Step 3: Verify link
        link_check = execute_command(ssh, "sudo dokku #{db_type}:links #{db_name}")

        result[:output] = output.join("\n")
        result[:success] = link_check&.include?(app_name)

        unless result[:success]
          result[:error] = "Database link verification failed"
        end
      end
    end
  rescue => e
    result[:error] = "Database configuration failed: #{e.message}"
  end

  result
end
```

### 4. Conditional Command Execution

**Check before executing:**

```ruby
def destroy_dokku_app(app_name)
  Net::SSH.start(...) do |ssh|
    # Check if app exists first
    app_check = execute_command(ssh, "sudo dokku apps:exists #{app_name} 2>&1")

    if app_check&.include?("does not exist")
      # App doesn't exist, consider it success
      result[:success] = true
      result[:output] = "App does not exist (already deleted)"
    else
      # App exists, destroy it
      destroy_output = execute_command(ssh,
        "sudo dokku apps:destroy #{app_name} --force 2>&1"
      )

      result[:success] = !destroy_output&.include?("ERROR")
      result[:output] = destroy_output
    end
  end
end
```

---

## Key Operations

### 1. Test Connection

**Purpose:** Verify SSH connectivity and credentials

```ruby
def test_connection
  result = { success: false, error: nil, connected: false }

  begin
    Timeout::timeout(CONNECTION_TIMEOUT) do
      Net::SSH.start(...) do |ssh|
        # Execute simple command
        test_output = ssh.exec!("echo 'Connection successful'")

        result[:success] = true
        result[:connected] = true
        @server.update!(
          connection_status: 'connected',
          last_connected_at: Time.current
        )
      end
    end
  rescue Net::SSH::AuthenticationFailed => e
    result[:error] = "Authentication failed"
    @server.update!(connection_status: 'failed')
  # ... other rescue clauses
  end

  result
end
```

### 2. Install Dokku

**Purpose:** Bootstrap Dokku on fresh server

```ruby
def install_dokku_with_key_setup
  result = { success: false, error: nil, dokku_installed: false }

  begin
    Timeout::timeout(INSTALL_TIMEOUT) do  # 15 minutes!
      Net::SSH.start(...) do |ssh|
        # Download and run Dokku installer
        install_script = <<~BASH
          wget https://raw.githubusercontent.com/dokku/dokku/master/bootstrap.sh
          sudo DOKKU_TAG=v0.28.0 bash bootstrap.sh
        BASH

        output = execute_command_with_streaming(ssh, install_script, channel)

        # Verify installation
        version = execute_command(ssh, "dokku version")
        result[:dokku_installed] = version.present?

        if result[:dokku_installed]
          @server.update!(dokku_version: version.strip)
          result[:success] = true
        end
      end
    end
  rescue Timeout::Error => e
    result[:error] = "Installation timeout (15 min limit). Check server performance."
  # ... other rescue clauses
  end

  result
end
```

### 3. Create Dokku App

**Purpose:** Create new app on Dokku server

```ruby
def create_dokku_app(app_name)
  result = { success: false, error: nil }

  begin
    Timeout::timeout(CONNECTION_TIMEOUT) do
      Net::SSH.start(...) do |ssh|
        # Create app
        create_output = execute_command(ssh,
          "sudo dokku apps:create #{app_name} 2>&1"
        )

        # Check for success/failure
        if create_output&.include?("already exists")
          result[:success] = true
          result[:output] = "App already exists"
        elsif create_output&.include?("Creating #{app_name}")
          result[:success] = true
          result[:output] = create_output
        else
          result[:error] = "App creation failed: #{create_output}"
        end

        @server.update!(last_connected_at: Time.current)
      end
    end
  rescue => e
    result[:error] = "App creation failed: #{e.message}"
  end

  result
end
```

### 4. Sync Environment Variables

**Purpose:** Update app configuration

```ruby
def sync_dokku_environment_variables(app_name, env_vars)
  result = { success: false, error: nil }

  begin
    Timeout::timeout(ENV_TIMEOUT) do  # 3 minutes
      Net::SSH.start(...) do |ssh|
        # Build config:set command
        # Example: dokku config:set myapp KEY1="value1" KEY2="value2"
        env_string = env_vars.map { |k, v| "#{k}=\"#{v}\"" }.join(' ')
        command = "sudo dokku config:set #{app_name} #{env_string}"

        # Execute with streaming (can be slow with many vars)
        output = execute_command_with_streaming(ssh, command, channel)

        result[:success] = !output&.include?("ERROR")
        result[:output] = output

        @server.update!(last_connected_at: Time.current)
      end
    end
  rescue Timeout::Error => e
    result[:error] = "Timeout syncing variables. Try reducing number of variables."
  # ... other rescue clauses
  end

  result
end
```

### 5. Configure SSL (Let's Encrypt)

**Purpose:** Enable HTTPS for app

```ruby
def enable_letsencrypt(app_name, email)
  result = { success: false, error: nil }

  begin
    Timeout::timeout(DOMAIN_TIMEOUT) do  # 10 minutes
      Net::SSH.start(...) do |ssh|
        # Set Let's Encrypt email
        execute_command(ssh,
          "sudo dokku config:set --global DOKKU_LETSENCRYPT_EMAIL=#{email}"
        )

        # Enable Let's Encrypt for app
        ssl_output = execute_command_with_streaming(ssh,
          "sudo dokku letsencrypt:enable #{app_name}",
          channel
        )

        # Verify SSL enabled
        ssl_check = execute_command(ssh,
          "sudo dokku letsencrypt:list | grep #{app_name}"
        )

        result[:success] = ssl_check.present? && !ssl_output&.include?("ERROR")
        result[:output] = ssl_output

        @server.update!(last_connected_at: Time.current)
      end
    end
  rescue Timeout::Error => e
    result[:error] = "SSL setup timeout. Domain verification may have failed."
  # ... other rescue clauses
  end

  result
end
```

---

## Performance Considerations

### 1. Connection Pooling (NOT Implemented)

**Current:** New SSH connection for each operation
**Impact:** Connection overhead (~1-2 seconds per operation)

**Potential improvement:**
```ruby
# Future enhancement: Connection pooling
class SshConnectionPool
  def with_connection(server)
    connection = @pool.fetch_or_create(server)
    yield connection
  ensure
    @pool.release(connection)
  end
end
```

**Trade-offs:**
- ✅ Faster sequential operations
- ✅ Reduced server load
- ❌ More complex connection management
- ❌ Stale connection handling needed

### 2. Parallel Operations (Limited)

**Current:** Sequential SSH operations
**Possible:** Parallel operations for independent tasks

**Example:**
```ruby
# Current (sequential): ~30 seconds
3.times do |i|
  service.create_dokku_app("app#{i}")
end

# Potential (parallel): ~10 seconds
threads = 3.times.map do |i|
  Thread.new { service.create_dokku_app("app#{i}") }
end
threads.each(&:join)
```

**Caution:** Test thoroughly - SSH connections are stateful!

### 3. Command Optimization

**Minimize roundtrips:**

```ruby
# ❌ BAD - 3 SSH connections
service.execute_command("dokku apps:list")
service.execute_command("dokku version")
service.execute_command("df -h")

# ✅ GOOD - 1 SSH connection
Net::SSH.start(...) do |ssh|
  apps = ssh.exec!("dokku apps:list")
  version = ssh.exec!("dokku version")
  disk = ssh.exec!("df -h")
end
```

---

## Testing SSH Operations

### 1. Mock SSH Connections

**Never make real SSH connections in tests:**

```ruby
# test/services/ssh_connection_service_test.rb
require 'test_helper'

class SshConnectionServiceTest < ActiveSupport::TestCase
  setup do
    @server = servers(:one)
    @service = SshConnectionService.new(@server)
  end

  test "test_connection returns success on valid credentials" do
    # Mock Net::SSH
    mock_ssh = mock('ssh')
    mock_ssh.expects(:exec!).with("echo 'Connection successful'").returns("Connection successful\n")

    Net::SSH.expects(:start).yields(mock_ssh).returns(true)

    result = @service.test_connection

    assert result[:success]
    assert result[:connected]
    assert_equal 'connected', @server.reload.connection_status
  end

  test "test_connection handles authentication failure" do
    Net::SSH.expects(:start).raises(Net::SSH::AuthenticationFailed)

    result = @service.test_connection

    refute result[:success]
    assert_includes result[:error], "Authentication failed"
    assert_equal 'failed', @server.reload.connection_status
  end
end
```

### 2. Integration Tests

**For manual/staging testing:**

```ruby
# test/integration/ssh_integration_test.rb
class SshIntegrationTest < ActionDispatch::IntegrationTest
  # Skip in CI, only run manually
  def test_real_ssh_connection
    skip unless ENV['RUN_SSH_TESTS']

    server = Server.create!(
      name: "Test Server",
      ip: ENV['TEST_SERVER_IP'],
      username: ENV['TEST_SERVER_USERNAME'],
      port: 22
    )

    service = SshConnectionService.new(server)
    result = service.test_connection

    assert result[:success], "SSH connection failed: #{result[:error]}"
  end
end
```

---

## Common Issues and Solutions

### Issue 1: Authentication Failed

**Symptoms:**
- "Authentication failed" error
- Cannot connect to server

**Possible causes:**
1. Wrong username
2. Invalid SSH key
3. SSH key permissions incorrect (not 0600)
4. Password incorrect
5. Server firewall blocking SSH

**Solutions:**
```bash
# Test SSH manually
ssh -i /path/to/key user@server-ip -p 22

# Check key permissions
ls -la ~/.ssh/id_ed25519
# Should show: -rw------- (0600)

# Fix permissions
chmod 600 ~/.ssh/id_ed25519

# Test password auth (if key fails)
ssh user@server-ip -p 22
```

**In code:**
```ruby
# Verify SSH key file permissions
key_path = AppSetting.get('dokku_ssh_key_path')
perms = File.stat(key_path).mode & 0777
if perms != 0600
  Rails.logger.warn "SSH key has incorrect permissions: #{perms.to_s(8)}"
  File.chmod(0600, key_path)
end
```

---

### Issue 2: Connection Timeout

**Symptoms:**
- "Connection timeout" error
- Operations hang for 10+ seconds

**Possible causes:**
1. Server is down
2. Firewall blocking SSH port
3. Wrong IP address
4. Network connectivity issues
5. Server overloaded

**Solutions:**
```bash
# Ping server
ping server-ip

# Test SSH port
telnet server-ip 22
# or
nc -zv server-ip 22

# Check firewall (if you have access)
sudo ufw status
sudo ufw allow 22/tcp
```

**In code:**
```ruby
# Increase timeout for slow servers
CONNECTION_TIMEOUT = ENV['SSH_TIMEOUT']&.to_i || 10

# Add retry logic (use cautiously)
def test_connection_with_retry(retries: 3)
  retries.times do |attempt|
    result = test_connection
    return result if result[:success]

    sleep(2 ** attempt)  # Exponential backoff
  end

  { success: false, error: "Failed after #{retries} attempts" }
end
```

---

### Issue 3: UTF-8 Encoding Errors

**Symptoms:**
- `ArgumentError: invalid byte sequence in UTF-8`
- ActionCable broadcasts crash
- Logs not saving to database

**Cause:**
SSH output contains invalid UTF-8 bytes

**Solution:**
**ALWAYS use `sanitize_utf8` before storing/broadcasting**

```ruby
# ✅ CORRECT
output = ssh.exec!("dokku ps:rebuild app")
clean_output = sanitize_utf8(output)
ActionCable.server.broadcast(channel, { data: clean_output })

# ❌ WRONG
output = ssh.exec!("dokku ps:rebuild app")
ActionCable.server.broadcast(channel, { data: output })  # May crash!
```

---

### Issue 4: Command Timeout

**Symptoms:**
- Long operations timeout
- "Operation timeout" error
- Incomplete deployments

**Possible causes:**
1. Timeout too short for operation
2. Server slow/overloaded
3. Large download (deployments, package updates)

**Solutions:**
```ruby
# Use appropriate timeout constant
def slow_operation
  Timeout::timeout(INSTALL_TIMEOUT) do  # 15 min for slow ops
    # ...
  end
end

# Or make timeout configurable
def operation_with_custom_timeout(custom_timeout: COMMAND_TIMEOUT)
  Timeout::timeout(custom_timeout) do
    # ...
  end
end
```

---

### Issue 5: SSH Key Not Found

**Symptoms:**
- "No such file or directory" error
- Empty `ssh_key_paths` array

**Cause:**
SSH key path configured but file doesn't exist

**Solution:**
```ruby
def ssh_key_paths
  paths = []

  if ENV['DOKKU_SSH_KEY_PATH'].present?
    path = ENV['DOKKU_SSH_KEY_PATH']
    if File.exist?(path)
      paths << path
    else
      Rails.logger.error "SSH key not found at: #{path}"
    end
  end

  # ... database AppSetting logic

  paths.compact
end
```

---

## Summary

### Key Takeaways

1. **SshConnectionService is critical** - All Dokku operations depend on it
2. **Always handle SSH exceptions** - Net::SSH can fail in many ways
3. **Use appropriate timeouts** - Different operations need different limits
4. **Sanitize UTF-8 output** - SSH output can contain invalid bytes
5. **Update last_connected_at** - Track server connectivity
6. **Return consistent hash** - `{ success:, error:, ... }`
7. **Log errors thoroughly** - Include backtrace for debugging
8. **Test with mocks** - Never make real SSH connections in tests

### Checklist for New SSH Operations

When adding new SSH operations:

- [ ] Use appropriate timeout constant
- [ ] Handle all SSH exceptions
- [ ] Sanitize UTF-8 output
- [ ] Update `server.last_connected_at` on success
- [ ] Return `{ success:, error:, output:, ... }` hash
- [ ] Log errors with Rails.logger
- [ ] Add tests with mocked SSH
- [ ] Document expected Dokku command output
- [ ] Consider streaming for long operations
- [ ] Verify Dokku command works manually first

### Related Documentation

- [CLAUDE.md](/CLAUDE.md) - SSH patterns and conventions
- [ARCHITECTURE.md](/docs/ARCHITECTURE.md) - Service layer design
- [deployment-system.md](/docs/features/deployment-system.md) - Deployment workflow (uses SSH)
- [CONVENTIONS.md](/docs/CONVENTIONS.md) - Service object patterns

---

**Remember:** SSH operations are the foundation of Vantage-Dokku. Handle them with care!
