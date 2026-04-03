# Debugging Guide

## Overview

Common debugging scenarios and solutions for Vantage-Dokku development.

---

## SSH Connection Issues

### Symptoms
- "Authentication failed"
- "Connection timeout"
- Cannot connect to server

### Debug Steps

**1. Test SSH manually:**
```bash
ssh -i /path/to/key user@server-ip -p 22
```

**2. Check key permissions:**
```bash
ls -la ~/.ssh/id_ed25519
# Should be: -rw------- (0600)

chmod 600 ~/.ssh/id_ed25519
```

**3. Verify server details:**
```ruby
rails console
server = Server.find_by(uuid: 'xxx')
puts server.connection_details
```

**4. Test connection service:**
```ruby
service = SshConnectionService.new(server)
result = service.test_connection
puts result.inspect
```

---

## ActionCable Issues

### Symptoms
- No real-time updates
- WebSocket not connecting
- "Failed to upgrade to WebSocket"

### Debug Steps

**1. Check APP_HOST:**
```bash
echo $APP_HOST
# Should match your domain/localhost:3000
```

**2. Check worker process:**
```bash
ps aux | grep solid_queue
# Should show running worker
```

**3. Browser console:**
```javascript
// Open dev tools → Console
// Look for WebSocket errors
```

**4. Check cable schema:**
```bash
rails runner "load Rails.root.join('db', 'cable_schema.rb')"
```

**5. Test broadcast:**
```ruby
ActionCable.server.broadcast('test', { message: 'hello' })
```

---

## Background Job Issues

### Symptoms
- Jobs not processing
- Deployments stuck in "pending"

### Debug Steps

**1. Check worker running:**
```bash
ps aux | grep solid_queue
```

**2. Check queue:**
```ruby
rails console
SolidQueue::Job.pending.count
SolidQueue::Job.all
```

**3. Check failed jobs:**
```ruby
SolidQueue::FailedExecution.all
SolidQueue::FailedExecution.last&.error
```

**4. Manually run job:**
```ruby
deployment = Deployment.last
DeploymentJob.perform_now(deployment)
```

---

## Database Issues

### Symptoms
- "PG::ConnectionBad"
- "Database does not exist"

### Solutions

**1. Create database:**
```bash
rails db:create
```

**2. Run migrations:**
```bash
rails db:migrate
```

**3. Load schemas:**
```bash
rails runner "load Rails.root.join('db', 'queue_schema.rb')"
rails runner "load Rails.root.join('db', 'cable_schema.rb')"
```

**4. Check connection:**
```bash
rails dbconsole
\l  -- List databases
\q  -- Quit
```

---

## Logs

**View logs:**
```bash
# Development
tail -f log/development.log

# Filter
tail -f log/development.log | grep DeploymentService

# Clear logs
> log/development.log
```

**Rails logger:**
```ruby
Rails.logger.info "Debug message"
Rails.logger.error "Error: #{e.message}"
Rails.logger.debug "Detailed info"
```

---

## Related Documentation

- [CLAUDE.md](/CLAUDE.md) - Debugging tips
- [ssh-integration.md](/docs/features/ssh-integration.md) - SSH troubleshooting
- [real-time-updates.md](/docs/features/real-time-updates.md) - ActionCable debugging

---

**When in doubt, check the logs!** 🔍
