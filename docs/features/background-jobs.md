# Background Jobs (SolidQueue)

## Overview

Vantage-Dokku uses **SolidQueue** for background job processing. SolidQueue is a database-backed job queue built for Rails 8, eliminating the need for Redis while providing reliable asynchronous job execution.

**Key Benefits:**
- No Redis dependency
- Database-backed (PostgreSQL)
- Reliable job persistence
- Simple deployment
- Built-in retry logic

---

## SolidQueue vs Sidekiq

| Feature | SolidQueue | Sidekiq |
|---------|------------|---------|
| **Storage** | PostgreSQL | Redis |
| **Dependencies** | None (DB only) | Redis server |
| **Persistence** | Permanent (DB) | Volatile (RAM) |
| **Scalability** | Moderate | High |
| **Best for** | Most applications | High-throughput apps |

**When to use SolidQueue:**
- Don't want Redis dependency
- Moderate job volume (<10,000/day)
- Prefer simpler infrastructure

**When to use Sidekiq:**
- Very high job volume (>100,000/day)
- Need advanced features (unique jobs, batches)
- Already using Redis

---

## Configuration

### Database Setup

**SolidQueue uses separate database schema:**

```yaml
# config/database.yml
production:
  primary:
    database: vantage_production

  queue:
    database: vantage_production
    migrations_paths: db/queue_migrate
```

**Load schema:**
```bash
# Create queue tables
rails runner "load Rails.root.join('db', 'queue_schema.rb')"
```

### Queue Configuration

**config/queue.yml:**
```yaml
production:
  dispatchers:
    - polling_interval: 1
      batch_size: 500

  workers:
    - queues: "*"
      threads: 5
      processes: 1
      polling_interval: 0.1
```

### Worker Processes

**Procfile:**
```
web: bundle exec puma -C config/puma.rb
worker: bundle exec rake solid_queue:start
```

**Scale workers:**
```bash
# Dokku
dokku ps:scale app-name web=1 worker=1

# Or manually
bundle exec rake solid_queue:start
```

---

## Job Patterns

### Creating a Job

```ruby
# app/jobs/example_job.rb
class ExampleJob < ApplicationJob
  queue_as :default

  def perform(resource, options = {})
    # Job logic here
    Rails.logger.info "Processing #{resource.class.name} ##{resource.id}"

    # Perform work
    result = SomeService.new(resource).perform

    # Handle result
    if result[:success]
      Rails.logger.info "Job completed successfully"
    else
      Rails.logger.error "Job failed: #{result[:error]}"
      raise StandardError, result[:error]  # Trigger retry
    end
  end
end
```

### Enqueuing Jobs

**Asynchronous (default):**
```ruby
# Enqueue for immediate processing
ExampleJob.perform_later(resource)

# Enqueue with delay
ExampleJob.set(wait: 5.minutes).perform_later(resource)

# Enqueue at specific time
ExampleJob.set(wait_until: tomorrow_noon).perform_later(resource)
```

**Synchronous (for testing/development):**
```ruby
ExampleJob.perform_now(resource)
```

### Queue Priority

```ruby
class HighPriorityJob < ApplicationJob
  queue_as :critical  # Processed first

class LowPriorityJob < ApplicationJob
  queue_as :default  # Standard priority

class BackgroundJob < ApplicationJob
  queue_as :low  # Processed last
```

---

## Example Jobs

### DeploymentJob

**Purpose:** Orchestrate deployments

```ruby
class DeploymentJob < ApplicationJob
  queue_as :default

  def perform(deployment)
    # Update status
    deployment.update!(deployment_status: 'deploying')

    # Broadcast start
    ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", {
      type: 'started'
    })

    # Execute deployment
    service = DeploymentService.new(deployment)
    result = service.deploy_from_repository

    # Update final status
    deployment.update!(
      deployment_status: result[:success] ? 'deployed' : 'failed'
    )

    # Broadcast completion
    ActionCable.server.broadcast("deployment_logs_#{deployment.uuid}", {
      type: 'completed',
      success: result[:success]
    })
  end
end
```

### ApplicationHealthCheckJob

**Purpose:** Monitor app health

```ruby
class ApplicationHealthCheckJob < ApplicationJob
  queue_as :default

  def perform
    Deployment.where.not(deployment_status: 'failed').find_each do |deployment|
      next unless deployment.can_deploy?

      service = ApplicationHealthService.new(deployment)
      result = service.check_health

      # Create health record
      ApplicationHealth.create!(
        deployment: deployment,
        status: result[:success] ? 'healthy' : 'unhealthy',
        response_time: result[:response_time],
        checked_at: Time.current
      )

      # Send notification if unhealthy
      if result[:success] == false && deployment.needs_health_notification?
        HealthNotificationJob.perform_later(deployment)
      end
    end
  end
end
```

**Recurring job setup:**
```ruby
# config/initializers/recurring_jobs.rb
Rails.application.config.after_initialize do
  SolidQueue::RecurringTask.find_or_create_by!(key: "health_checks") do |task|
    task.schedule = "*/5 * * * *"  # Every 5 minutes
    task.command = "ApplicationHealthCheckJob.perform_later"
  end
end
```

---

## Error Handling

### Retry Logic

**SolidQueue automatically retries failed jobs:**

```ruby
class RetryableJob < ApplicationJob
  # Default: 25 retries with exponential backoff
  retry_on StandardError, wait: :exponentially_longer, attempts: 5

  # Specific error handling
  retry_on Net::SSH::ConnectionTimeout, wait: 30.seconds, attempts: 3
  discard_on ActiveRecord::RecordNotFound  # Don't retry

  def perform(resource)
    # Job logic
    raise StandardError, "Temporary failure" if rand < 0.5
  end
end
```

**Retry schedule:**
- Attempt 1: Immediate
- Attempt 2: 3 seconds
- Attempt 3: 18 seconds
- Attempt 4: 83 seconds
- Attempt 5: 259 seconds

### Error Tracking

**Check failed jobs:**
```ruby
# Rails console
SolidQueue::FailedExecution.all
SolidQueue::FailedExecution.last.error
SolidQueue::FailedExecution.last.exception_executions
```

**Manually retry:**
```ruby
failed = SolidQueue::FailedExecution.last
failed.retry  # Re-enqueue job
```

---

## Monitoring

### Job Queue Status

**Check pending jobs:**
```ruby
SolidQueue::Job.pending.count
SolidQueue::Job.where(queue_name: 'default').count
```

**Check running jobs:**
```ruby
SolidQueue::Job.running.count
```

**Check failed jobs:**
```ruby
SolidQueue::FailedExecution.count
SolidQueue::FailedExecution.recent.limit(10)
```

### Worker Status

**Check active workers:**
```ruby
SolidQueue::Process.all
SolidQueue::Process.count  # Should be > 0
```

**Worker not running?**
```bash
# Check process
ps aux | grep solid_queue

# Start worker
bundle exec rake solid_queue:start
```

---

## Best Practices

### 1. Keep Jobs Small

**Bad:**
```ruby
class MassiveJob < ApplicationJob
  def perform
    # 1000 different operations
    User.all.each { |user| process_user(user) }
    Server.all.each { |server| update_server(server) }
    # ... 50 more operations
  end
end
```

**Good:**
```ruby
class ProcessUserJob < ApplicationJob
  def perform(user)
    # Single focused operation
    UserProcessor.new(user).process
  end
end

# Enqueue many small jobs
User.find_each { |user| ProcessUserJob.perform_later(user) }
```

### 2. Use Idempotent Operations

**Jobs may run multiple times (retries):**
```ruby
class IdempotentJob < ApplicationJob
  def perform(resource_id)
    resource = Resource.find(resource_id)

    # Check if already processed
    return if resource.processed?

    # Perform work
    resource.process!

    # Mark as processed
    resource.update!(processed: true)
  end
end
```

### 3. Handle Failures Gracefully

```ruby
class GracefulJob < ApplicationJob
  def perform(deployment)
    begin
      # Risky operation
      result = external_api_call(deployment)
    rescue ExternalApiError => e
      # Log error
      Rails.logger.error "API call failed: #{e.message}"

      # Update model
      deployment.update!(
        status: 'failed',
        error_message: e.message
      )

      # Don't raise - job shouldn't retry for this error
      return
    end

    # Continue with success
    deployment.update!(status: 'completed')
  end
end
```

---

## Related Documentation

- [CLAUDE.md](/CLAUDE.md) - Background job patterns
- [ARCHITECTURE.md](/docs/ARCHITECTURE.md) - Job layer architecture
- [deployment-system.md](/docs/features/deployment-system.md) - DeploymentJob details

---

**Background jobs power Vantage-Dokku. Keep them fast and reliable!** ⚙️
