# Authentication & Authorization

## Overview

Vantage-Dokku uses **Devise** for authentication and **Pundit + Rolify** for authorization. This provides secure user management, OAuth integration, role-based access control, and comprehensive activity logging.

**Key Features:**
- Email/password authentication
- Google OAuth login
- Role-based permissions (Admin, Moderator)
- Activity logging for audit trails
- Email confirmation (optional)
- Password reset functionality

---

## Table of Contents

1. [Authentication Stack](#authentication-stack)
2. [User Registration](#user-registration)
3. [Login Flow](#login-flow)
4. [Google OAuth](#google-oauth)
5. [Password Reset](#password-reset)
6. [Role-Based Access Control](#role-based-access-control)
7. [Authorization Policies](#authorization-policies)
8. [Activity Logging](#activity-logging)
9. [Session Management](#session-management)
10. [Security Features](#security-features)

---

## Authentication Stack

### Technologies

**Devise** - Authentication framework
- Confirmable (email confirmation)
- Recoverable (password reset)
- Rememberable (remember me checkbox)
- Validatable (email/password validation)
- Trackable (sign-in count, timestamps, IP)

**OmniAuth** - OAuth framework
- omniauth-google-oauth2 (Google login)
- Supports multiple providers

**Pundit** - Authorization library
- Policy-based permissions
- Resource-level authorization

**Rolify** - Role management
- Database-backed roles
- User-role association

### Database Schema

**users table:**
```ruby
create_table "users" do |t|
  # Devise fields
  t.string   "email",              default: "", null: false
  t.string   "encrypted_password", default: "", null: false

  # Recoverable
  t.string   "reset_password_token"
  t.datetime "reset_password_sent_at"

  # Rememberable
  t.datetime "remember_created_at"

  # Trackable
  t.integer  "sign_in_count", default: 0
  t.datetime "current_sign_in_at"
  t.datetime "last_sign_in_at"
  t.string   "current_sign_in_ip"
  t.string   "last_sign_in_ip"

  # Confirmable
  t.string   "confirmation_token"
  t.datetime "confirmed_at"
  t.datetime "confirmation_sent_at"
  t.string   "unconfirmed_email"

  # Profile fields
  t.string   "first_name"
  t.string   "last_name"
  t.string   "theme", default: "auto"

  t.timestamps
end
```

---

## User Registration

### Standard Registration

**Route:** `/users/sign_up`

**Form fields:**
- Email address
- Password (minimum 6 characters)
- Password confirmation
- First name (optional)
- Last name (optional)

**Process:**
```ruby
# 1. Submit registration form
POST /users

# 2. Create user
user = User.create!(
  email: params[:email],
  password: params[:password],
  password_confirmation: params[:password_confirmation],
  first_name: params[:first_name],
  last_name: params[:last_name]
)

# 3. Send confirmation email (if enabled)
if confirmable_enabled?
  UserMailer.confirmation_instructions(user).deliver_later
end

# 4. Log activity
ActivityLog.log_activity(
  user: user,
  action: 'user_registered',
  details: "New user registration"
)

# 5. Redirect to login or dashboard
```

### Email Confirmation

**If enabled:**
1. User receives confirmation email
2. Click confirmation link
3. Email verified
4. Can now log in

**If disabled:**
```ruby
# config/initializers/devise.rb
config.reconfirmable = false

# Or via AppSetting
AppSetting.set('require_email_confirmation', 'false')

# Auto-confirm users
user.skip_confirmation!
user.save
```

### Validation Rules

**Email:**
- Must be present
- Must be valid format
- Must be unique (case-insensitive)

**Password:**
- Minimum 6 characters
- Must match confirmation
- Not too common (Devise checks common passwords)

---

## Login Flow

### Email/Password Login

**Route:** `/users/sign_in`

**Process:**
```ruby
# 1. Submit login form
POST /users/sign_in
{
  user: {
    email: 'user@example.com',
    password: 'password123',
    remember_me: '1'
  }
}

# 2. Devise validates credentials
user = User.find_by(email: params[:user][:email])
if user && user.valid_password?(params[:user][:password])
  # Success - create session
else
  # Failure - show error
end

# 3. Check if confirmed (if confirmable enabled)
unless user.confirmed?
  redirect_to new_user_confirmation_path
  return
end

# 4. Update tracking fields
user.update!(
  sign_in_count: user.sign_in_count + 1,
  current_sign_in_at: Time.current,
  current_sign_in_ip: request.remote_ip,
  last_sign_in_at: user.current_sign_in_at,
  last_sign_in_ip: user.current_sign_in_ip
)

# 5. Create session
sign_in(user)

# 6. Log activity
log_login(user)

# 7. Redirect to dashboard
redirect_to dashboard_path
```

### Remember Me

**Checkbox on login form:**
- Creates persistent cookie
- Session lasts 2 weeks (configurable)
- User stays logged in across browser closes

**Configuration:**
```ruby
# config/initializers/devise.rb
config.remember_for = 2.weeks
```

---

## Google OAuth

### Setup

**1. Google Cloud Console:**
- Create OAuth 2.0 credentials
- Add authorized redirect URI:
  ```
  http://localhost:3000/users/auth/google_oauth2/callback  # Dev
  https://yourdomain.com/users/auth/google_oauth2/callback  # Prod
  ```

**2. Configure environment variables:**
```bash
# .env
GOOGLE_CLIENT_ID=your-client-id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your-client-secret
```

**3. Devise OmniAuth configuration:**
```ruby
# config/initializers/devise.rb
config.omniauth :google_oauth2,
  ENV['GOOGLE_CLIENT_ID'],
  ENV['GOOGLE_CLIENT_SECRET'],
  scope: 'email,profile'
```

### OAuth Flow

**1. User clicks "Sign in with Google"**
```html
<%= button_to "Sign in with Google",
    user_google_oauth2_omniauth_authorize_path,
    method: :post,
    data: { turbo: false } %>
```

**2. Redirect to Google**
```
https://accounts.google.com/o/oauth2/auth?
  client_id=YOUR_CLIENT_ID&
  redirect_uri=http://localhost:3000/users/auth/google_oauth2/callback&
  scope=email+profile&
  response_type=code
```

**3. User authorizes**
- Google shows consent screen
- User approves access to email/profile

**4. Google redirects back with code**
```
http://localhost:3000/users/auth/google_oauth2/callback?code=AUTHORIZATION_CODE
```

**5. Exchange code for access token**
```ruby
# OmniAuth middleware handles this automatically
# Receives user data:
{
  provider: 'google_oauth2',
  uid: '1234567890',
  info: {
    email: 'user@gmail.com',
    name: 'John Doe',
    first_name: 'John',
    last_name: 'Doe',
    image: 'https://lh3.googleusercontent.com/...'
  },
  credentials: {
    token: 'ACCESS_TOKEN',
    refresh_token: 'REFRESH_TOKEN',
    expires_at: 1234567890
  }
}
```

**6. Create or update user**
```ruby
# app/models/user.rb
def self.from_omniauth(auth)
  user = User.find_or_initialize_by(email: auth.info.email)

  user.assign_attributes(
    provider: auth.provider,
    uid: auth.uid,
    first_name: auth.info.first_name,
    last_name: auth.info.last_name,
    password: Devise.friendly_token[0, 20] # Random password
  )

  user.skip_confirmation!  # Auto-confirm OAuth users
  user.save!

  # Create or update LinkedAccount
  LinkedAccount.find_or_create_by!(
    user: user,
    provider: auth.provider,
    uid: auth.uid
  ).update!(
    access_token: auth.credentials.token,
    refresh_token: auth.credentials.refresh_token,
    expires_at: Time.at(auth.credentials.expires_at)
  )

  user
end
```

**7. Sign in user**
```ruby
# app/controllers/users/omniauth_callbacks_controller.rb
def google_oauth2
  @user = User.from_omniauth(request.env['omniauth.auth'])

  if @user.persisted?
    sign_in_and_redirect @user
    set_flash_message(:notice, :success, kind: 'Google')
  else
    redirect_to new_user_registration_url
  end
end
```

---

## Password Reset

### Request Reset

**1. User clicks "Forgot password?"**

**2. Enter email address**
```ruby
POST /users/password
{
  user: {
    email: 'user@example.com'
  }
}
```

**3. Send reset email**
```ruby
# Devise generates reset token
user.send_reset_password_instructions

# Email contains link:
# http://localhost:3000/users/password/edit?reset_password_token=TOKEN
```

**4. Email sent confirmation**
```
If your email address exists in our database, you will receive a
password recovery link at your email address in a few minutes.
```

### Reset Password

**1. Click link in email**

**2. Enter new password**
```ruby
PATCH /users/password
{
  user: {
    reset_password_token: 'TOKEN',
    password: 'newpassword123',
    password_confirmation: 'newpassword123'
  }
}
```

**3. Validate token and update password**
```ruby
user = User.reset_password_by_token(params[:user])

if user.errors.empty?
  # Success
  sign_in(user)
  redirect_to dashboard_path, notice: 'Password changed successfully'
else
  # Failure (invalid/expired token)
  render :edit
end
```

**4. Log activity**
```ruby
log_password_change(user)
```

---

## Role-Based Access Control

### Roles

**Available roles:**
- **Admin** - Full system access
- **Moderator** - Limited administrative access
- **User** - Default role (no special permissions)

### Rolify Integration

**Assign role:**
```ruby
user = User.find_by(email: 'admin@example.com')
user.add_role(:admin)

# Check role
user.has_role?(:admin)  # => true
```

**Remove role:**
```ruby
user.remove_role(:admin)
```

**Database schema:**
```ruby
# roles table
create_table "roles" do |t|
  t.string "name"
  t.string "resource_type"
  t.bigint "resource_id"
  t.timestamps
end

# users_roles join table
create_table "users_roles", id: false do |t|
  t.bigint "user_id"
  t.bigint "role_id"
end
```

### Admin Capabilities

**Admins can:**
- View all servers/deployments (all users)
- Manage users (view, edit, delete)
- View activity logs
- Configure system settings (SMTP, OAuth)
- Assign/remove roles

**Regular users can:**
- View only their own servers/deployments
- Cannot access admin area
- Cannot view other users' resources

---

## Authorization Policies

### Pundit Policies

**Example: ServerPolicy**
```ruby
# app/policies/server_policy.rb
class ServerPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      if user.has_role?(:admin)
        scope.all  # Admins see all servers
      else
        scope.where(user: user)  # Users see only their servers
      end
    end
  end

  def index?
    true  # Anyone can view index
  end

  def show?
    user.has_role?(:admin) || record.user == user
  end

  def create?
    true  # Any user can create
  end

  def update?
    user.has_role?(:admin) || record.user == user
  end

  def destroy?
    user.has_role?(:admin) || record.user == user
  end
end
```

### Controller Authorization

**Every action must authorize:**
```ruby
class ServersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_server, only: [:show, :edit, :update, :destroy]

  def index
    @servers = policy_scope(Server)  # Scoped to user
  end

  def show
    authorize @server  # Raises Pundit::NotAuthorizedError if unauthorized
  end

  def create
    @server = current_user.servers.build(server_params)
    authorize @server

    if @server.save
      redirect_to @server
    else
      render :new
    end
  end

  private

  def set_server
    @server = Server.find_by!(uuid: params[:uuid])
  end
end
```

### Unauthorized Access Handling

```ruby
# app/controllers/application_controller.rb
rescue_from Pundit::NotAuthorizedError do |exception|
  redirect_to root_path, alert: 'You are not authorized to perform this action.'
end
```

---

## Activity Logging

### What Gets Logged

**All significant user actions:**
- Login/logout
- Profile updates
- Password changes
- Server creation/update/deletion
- Deployment creation/deletion
- Settings changes
- Role assignments

### ActivityLog Model

```ruby
class ActivityLog < ApplicationRecord
  belongs_to :user

  # Fields:
  # - user_id
  # - action (string) - Action performed
  # - details (text) - Additional details
  # - ip_address (string) - Request IP
  # - user_agent (string) - Browser/client
  # - controller_name (string)
  # - action_name (string)
  # - params (jsonb) - Filtered params
  # - created_at
end
```

### Logging in Controllers

```ruby
# Include ActivityTrackable concern
class ServersController < ApplicationController
  include ActivityTrackable

  def create
    @server = current_user.servers.build(server_params)

    if @server.save
      log_activity("Created server", details: "Server: #{@server.name}")
      redirect_to @server
    else
      render :new
    end
  end

  def destroy
    @server.destroy
    log_activity("Deleted server", details: "Server: #{@server.name}")
    redirect_to servers_path
  end
end
```

### Viewing Activity Logs

**Admin dashboard:**
```ruby
# app/controllers/admin/activity_logs_controller.rb
def index
  @activity_logs = ActivityLog
    .includes(:user)
    .order(created_at: :desc)
    .page(params[:page])
end
```

**Per-user activity:**
```ruby
@user_activity = current_user.activity_logs.recent.limit(50)
```

---

## Session Management

### Session Storage

**Rails encrypted cookies:**
- Encrypted with `SECRET_KEY_BASE`
- Signed to prevent tampering
- Max size: 4KB

**Session contents:**
```ruby
session[:user_id]  # User ID
session[:expires_at]  # Expiration time
# Devise adds additional data
```

### Session Timeout

**Configuration:**
```ruby
# config/initializers/devise.rb
config.timeout_in = 30.minutes

# Session expires after 30 minutes of inactivity
```

**Manual logout:**
```ruby
# app/controllers/users/sessions_controller.rb
def destroy
  log_logout(current_user)
  sign_out(current_user)
  redirect_to root_path, notice: 'Signed out successfully'
end
```

---

## Security Features

### Password Security

**BCrypt hashing:**
- Passwords never stored in plain text
- Cost factor: 12 (configurable)
- Salted automatically

**Password validation:**
- Minimum length: 6 characters
- Complexity requirements (optional)
- Common password blacklist (Devise default)

### CSRF Protection

**Rails CSRF tokens:**
```html
<%= form_with model: @server do |f| %>
  <%= hidden_field_tag :authenticity_token, form_authenticity_token %>
  <!-- form fields -->
<% end %>
```

**API requests:**
```ruby
# Verify CSRF token
protect_from_forgery with: :exception
```

### Secure Cookies

**Configuration:**
```ruby
# config/environments/production.rb
config.force_ssl = true  # HTTPS only

# config/initializers/session_store.rb
Rails.application.config.session_store :cookie_store,
  key: '_vantage_session',
  secure: Rails.env.production?,  # HTTPS only in production
  httponly: true,  # No JavaScript access
  same_site: :lax  # CSRF protection
```

### Rate Limiting

**Login attempts (via Rack::Attack):**
```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle('logins/email', limit: 5, period: 20.minutes) do |req|
  if req.path == '/users/sign_in' && req.post?
    req.params['user']['email']
  end
end
```

---

## Summary

### Key Takeaways

1. **Devise** handles authentication (login, registration, password reset)
2. **OmniAuth** enables Google OAuth login
3. **Pundit** enforces authorization at controller level
4. **Rolify** manages user roles (Admin, Moderator)
5. **ActivityLog** tracks all user actions for auditing
6. **Encrypted cookies** store sessions securely

### Best Practices

**For users:**
- Use strong passwords (min 12 characters)
- Enable 2FA if available
- Log out on shared devices

**For developers:**
- Always call `authorize @resource` in controllers
- Use `policy_scope` for index actions
- Log significant actions with `log_activity`
- Never skip authentication checks
- Test authorization policies

### Related Documentation

- [CLAUDE.md](/CLAUDE.md) - Security considerations
- [ARCHITECTURE.md](/docs/ARCHITECTURE.md) - Security architecture
- [CONVENTIONS.md](/docs/CONVENTIONS.md) - Authorization patterns

---

**Security first, always!** 🔒
