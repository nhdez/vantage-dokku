# Common Development Tasks

## Quick Reference

Common operations for Vantage-Dokku development.

---

## Adding a New Model

```bash
# Generate model with UUID
rails g model MyModel name:string uuid:string:uniq

# Edit migration
# Add: t.string :uuid, null: false
# Add: t.index :uuid, unique: true

# Run migration
rails db:migrate

# Edit model
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

# Update routes
resources :my_models, param: :uuid
```

---

## Adding a Background Job

```bash
# Generate job
rails g job my_operation

# Edit job
class MyOperationJob < ApplicationJob
  queue_as :default

  def perform(resource)
    # Update status
    resource.update!(status: 'processing')

    # Broadcast start
    ActionCable.server.broadcast("channel_#{resource.uuid}", {
      type: 'started'
    })

    # Perform work
    result = MyService.new(resource).perform

    # Update final status
    resource.update!(status: result[:success] ? 'completed' : 'failed')

    # Broadcast completion
    ActionCable.server.broadcast("channel_#{resource.uuid}", {
      type: 'completed',
      success: result[:success]
    })
  end
end

# Call from controller
MyOperationJob.perform_later(@resource)
```

---

## Adding an ActionCable Channel

```bash
# Generate channel
rails g channel my_operation

# Edit channel
class MyOperationChannel < ApplicationCable::Channel
  def subscribed
    resource_uuid = params[:uuid]
    stream_from "my_operation_#{resource_uuid}"
  end

  def unsubscribed
    stop_all_streams
  end
end

# Broadcast from job/service
ActionCable.server.broadcast("my_operation_#{uuid}", data)
```

---

## Database Migrations

```bash
# Create migration
rails g migration AddFieldToModel field:type

# Edit migration
class AddFieldToModel < ActiveRecord::Migration[8.0]
  def change
    add_column :models, :field, :string
    add_index :models, :field
  end
end

# Run migration
rails db:migrate

# Rollback
rails db:rollback

# Redo
rails db:migrate:redo

# Status
rails db:migrate:status
```

---

## Adding SSH Operations

```ruby
# app/services/ssh_connection_service.rb
def my_ssh_operation(app_name)
  result = { success: false, error: nil, output: '' }

  begin
    Timeout::timeout(COMMAND_TIMEOUT) do
      Net::SSH.start(@connection_details[:host],
                     @connection_details[:username],
                     ssh_options) do |ssh|
        result[:output] = execute_command(ssh, "dokku my:command #{app_name}")
        result[:success] = true
        @server.update!(last_connected_at: Time.current)
      end
    end
  rescue Net::SSH::AuthenticationFailed => e
    result[:error] = "Authentication failed"
  rescue Net::SSH::ConnectionTimeout => e
    result[:error] = "Connection timeout"
  rescue StandardError => e
    result[:error] = "Operation failed: #{e.message}"
  end

  result
end
```

---

## Adding a Pundit Policy

```bash
# Generate policy
rails g pundit:policy my_model

# Edit policy
class MyModelPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_role?(:admin)
        scope.all
      else
        scope.where(user: user)
      end
    end
  end

  def show?
    user.has_role?(:admin) || record.user == user
  end

  def create?
    true
  end

  def update?
    user.has_role?(:admin) || record.user == user
  end

  def destroy?
    user.has_role?(:admin) || record.user == user
  end
end

# Use in controller
def show
  @my_model = MyModel.find_by!(uuid: params[:uuid])
  authorize @my_model
end
```

---

## Rails Console Helpers

```ruby
# Find resources
User.find_by(email: 'admin@example.com')
Server.find_by(uuid: 'xxx')
Deployment.where(deployment_status: 'deployed')

# Test services
server = Server.first
service = SshConnectionService.new(server)
result = service.test_connection

# Check jobs
SolidQueue::Job.pending.count
SolidQueue::FailedExecution.last

# Broadcast test
ActionCable.server.broadcast('test', { message: 'hello' })

# Assign role
user = User.first
user.add_role(:admin)
```

---

## Related Documentation

- [CLAUDE.md](/CLAUDE.md) - Development patterns
- [CONVENTIONS.md](/docs/CONVENTIONS.md) - Code standards

---

**Keep this handy for quick reference!** 📚
