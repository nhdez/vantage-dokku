# Testing Guide

## Overview

Vantage-Dokku uses **Minitest** (Rails default) for testing. This guide covers testing patterns, best practices, and common scenarios.

---

## Test Structure

```
test/
├── models/           # Model tests
├── controllers/      # Controller tests
├── jobs/             # Background job tests
├── services/         # Service object tests
├── policies/         # Pundit policy tests
├── system/           # System/integration tests
├── fixtures/         # Test data
└── test_helper.rb    # Test configuration
```

---

## Running Tests

```bash
# All tests
rails test

# Specific file
rails test test/models/server_test.rb

# Specific test
rails test test/models/server_test.rb:10

# System tests
rails test:system

# With coverage
COVERAGE=true rails test
```

---

## Model Testing

```ruby
require "test_helper"

class ServerTest < ActiveSupport::TestCase
  test "should generate UUID on creation" do
    server = Server.new(name: "Test", ip: "1.2.3.4", username: "dokku", port: 22)
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

---

## Controller Testing

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
      post servers_url, params: {
        server: {
          name: "Test",
          ip: "1.2.3.4",
          username: "dokku",
          port: 22
        }
      }
    end
    assert_redirected_to server_url(Server.last)
  end
end
```

---

## Job Testing

**Mock SSH connections:**
```ruby
require "test_helper"

class DeploymentJobTest < ActiveSupport::TestCase
  test "should update deployment status" do
    deployment = deployments(:one)

    # Mock SSH service
    SshConnectionService.any_instance.stubs(:test_connection).returns({
      success: true
    })

    DeploymentJob.perform_now(deployment)

    assert_equal 'deployed', deployment.reload.deployment_status
  end
end
```

---

## Related Documentation

- [CLAUDE.md](/CLAUDE.md) - Testing conventions
- [CONVENTIONS.md](/docs/CONVENTIONS.md) - Test patterns

---

**Test early, test often!** ✅
