# Vantage Dokku - Complete Dokku Management Platform

[![Rails Version](https://img.shields.io/badge/rails-8.0.2-red.svg)](https://rubyonrails.org/)
[![Ruby Version](https://img.shields.io/badge/ruby-3.2+-red.svg)](https://www.ruby-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

![vantage_bp](https://github.com/user-attachments/assets/68761cc4-89f7-42f7-bc82-5b8a3cadb7b0)

A comprehensive Dokku deployment management platform built with Rails 8. Manage your servers, deploy applications from GitHub repositories, configure domains with SSL, and monitor deployments with real-time logs. Features a beautiful Material Design interface with advanced theming, GitHub integration, and powerful background job processing.

## ✨ Features

### 🚀 Dokku Server Management
- **Server Dashboard** - Manage multiple Dokku servers from a single interface
- **SSH Connection Testing** - Automated server connectivity verification
- **Dokku Installation Status** - Real-time monitoring of Dokku installation and version
- **Secure Authentication** - SSH key-based server authentication with password fallback
- **Health Monitoring** - Automated server health checks and status tracking

### 📦 Application Deployment
- **GitHub Integration** - Deploy directly from your GitHub repositories with OAuth authentication
- **Public Repository Support** - Deploy from any publicly accessible Git repository
- **Manual Git Push** - Traditional Dokku workflow with git remote configuration
- **Background Processing** - Non-blocking deployments with SolidQueue job processing
- **Real-time Logs** - Live deployment monitoring with auto-refreshing terminal-style logs
- **Deployment History** - Track deployment status, timing, and outcomes

### 🌐 Domain & SSL Management
- **Custom Domain Configuration** - Add and manage custom domains for your applications
- **Automatic SSL** - Let's Encrypt integration with automatic certificate management
- **SSL Status Monitoring** - Real-time SSL certificate verification and expiry tracking
- **Default Domain Support** - Automatic .nip.io domain generation for quick access

### 🔑 Infrastructure Management
- **SSH Key Management** - Centralized SSH key storage and deployment to servers
- **Environment Variables** - Secure management of application environment configuration
- **Database Configuration** - PostgreSQL, MySQL, Redis, and custom database setup
- **Resource Monitoring** - Application health checks and performance tracking

### 🔗 GitHub Integration
- **OAuth Authentication** - Secure GitHub account linking with personal access tokens
- **Repository Browser** - Visual selection of repositories from connected GitHub accounts
- **Branch Selection** - Deploy from any branch with real-time branch detection
- **Connection Testing** - Automated GitHub API connectivity verification

### 🔐 Authentication & Authorization
- **Devise Authentication** - Complete user management with sign-up, sign-in, password recovery
- **Google OAuth Integration** - One-click sign-in with Google accounts
- **Role-Based Access Control** - Powered by Rolify with granular permissions
- **Multi-tenant Security** - Users can only manage their own servers and deployments

### 🎨 Modern UI & Experience
- **MDBootstrap Material Design** - Beautiful, responsive Material Design components
- **Advanced Dark Mode** - System-aware theme switching with manual override options
- **Real-time Updates** - Live status updates and progress monitoring
- **Responsive Design** - Mobile-first approach optimized for all device sizes
- **Toast Notifications** - Beautiful animated notifications for all actions

### 🛡️ Admin Panel
- **System Dashboard** - Server and deployment statistics overview
- **User Management** - Advanced search, filtering, and role assignment
- **SMTP Configuration** - Email settings with environment variable support
- **OAuth Settings** - Google OAuth credential management
- **Activity Monitoring** - Comprehensive audit logs with filtering and search

## 🚀 Quick Start

### Prerequisites
- Ruby 3.2+
- Rails 8.0.2
- PostgreSQL
- Node.js (for asset pipeline)
- One or more servers with Dokku installed for deployment management

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd vantage-dokku
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

3. **Generate encryption keys**
   ```bash
   rails db:encryption:init
   ```
   Save the output - you'll need these keys for production!

4. **Database setup**
   ```bash
   rails db:create
   rails db:migrate
   rails db:seed
   ```

5. **Setup SolidQueue (Background Jobs)**
   ```bash
   # SolidQueue tables should be created by migration, but if needed:
   rails runner "load Rails.root.join('db', 'queue_schema.rb')"
   ```

6. **Start the server**
   ```bash
   rails server
   ```

7. **Access the application**
   - Application: http://localhost:3000
   - Admin login: `admin@vantage.com` / `password123`

### First Steps
1. **Add a Server**: Go to Dashboard → Servers → Add Server
2. **Link GitHub Account**: Go to Dashboard → Linked Accounts → Link GitHub
3. **Create Deployment**: Go to Dashboard → Deployments → New Deployment
4. **Configure Git**: Set up repository source in Git Configuration
5. **Deploy**: Click the Deploy button and monitor logs!

## ⚙️ Configuration

### Environment Variables

Create a `.env` file for development:

```env
# Database
DATABASE_URL=postgresql://username:password@localhost/vantage_dokku_development

# Google OAuth (Configure via Admin Panel or ENV)
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret

# SMTP (Can configure via Admin Panel or ENV)
USE_REAL_EMAIL=false
SMTP_ADDRESS=email-smtp.region.amazonaws.com
SMTP_PORT=587
SMTP_DOMAIN=yourdomain.com
SMTP_USERNAME=your_smtp_username
SMTP_PASSWORD=your_smtp_password
SMTP_AUTHENTICATION=login
MAIL_FROM=no-reply@yourdomain.com
```

### Production Environment (Critical!)

Production requires additional configuration for secure token storage and background jobs:

```env
# Active Record Encryption (REQUIRED for GitHub token storage)
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=your_primary_key
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=your_deterministic_key  
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=your_key_derivation_salt

# Database
DATABASE_URL=postgresql://username:password@hostname/database_production

# Email Configuration
USE_REAL_EMAIL=true
SMTP_ADDRESS=email-smtp.eu-west-2.amazonaws.com
SMTP_PORT=587
SMTP_DOMAIN=yourdomain.com
SMTP_USERNAME=your_aws_ses_username
SMTP_PASSWORD=your_aws_ses_password
SMTP_AUTHENTICATION=login
MAIL_FROM=no-reply@yourdomain.com

# OAuth
GOOGLE_CLIENT_ID=production_google_client_id
GOOGLE_CLIENT_SECRET=production_google_client_secret
```

### Production Deployment Checklist

⚠️ **These steps are critical for successful production deployment:**

1. **Generate and configure encryption keys**:
   ```bash
   rails db:encryption:init
   ```
   Add the generated keys to your production environment variables or credentials

2. **Run database migrations**:
   ```bash
   # In production (Dokku example)
   dokku run your-app rails db:migrate
   ```

3. **Verify SolidQueue tables exist**:
   ```bash
   # Should be created by migration, but if issues:
   dokku run your-app rails runner "load Rails.root.join('db', 'queue_schema.rb')"
   ```

4. **Set up SMTP environment variables** (easier than admin panel for production)

5. **Configure SSL/TLS for your domain**

### GitHub OAuth Setup

1. Visit [Google Cloud Console](https://console.cloud.google.com)
2. Create OAuth 2.0 credentials  
3. Add authorized redirect URIs:
   - Development: `http://localhost:3000/users/auth/google_oauth2/callback`
   - Production: `https://yourdomain.com/users/auth/google_oauth2/callback`
4. Configure via Admin → OAuth Settings or environment variables

### GitHub Integration

Users can link their GitHub accounts to deploy private repositories:
1. Go to GitHub → Settings → Developer settings → Personal access tokens
2. Generate a classic token with `repo` and `read:user` permissions
3. Link account in Vantage Dokku → Linked Accounts

## 🏗️ Architecture

### Core Models

#### Server Model (`app/models/server.rb`)
- **SSH Connectivity**: Secure server connections with key-based authentication
- **Dokku Integration**: Automated Dokku installation detection and version monitoring
- **Health Monitoring**: Periodic connectivity and status checks
- **Multi-tenant**: Users can only access their own servers

#### Deployment Model (`app/models/deployment.rb`)
- **Git Integration**: Support for GitHub repos, public repos, and manual deployment
- **Background Processing**: Asynchronous deployment with status tracking
- **Domain Management**: Custom domain configuration with SSL support
- **Resource Configuration**: Environment variables, databases, SSH keys

#### LinkedAccount Model (`app/models/linked_account.rb`)
- **GitHub Integration**: OAuth token storage with encryption
- **Connection Testing**: Automated GitHub API connectivity verification
- **Token Management**: Secure encrypted storage of access tokens
- **Repository Access**: Fetch user repositories and organization data

#### Domain Model (`app/models/domain.rb`)
- **SSL Management**: Let's Encrypt integration with automatic verification
- **Multi-domain Support**: Multiple domains per deployment
- **Health Monitoring**: SSL certificate expiry and validity checking
- **Default Domains**: Automatic .nip.io domain generation

#### EnvironmentVariable Model (`app/models/environment_variable.rb`)
- **Secure Storage**: Encrypted environment variable management
- **Deployment Integration**: Automatic deployment to Dokku servers
- **Validation**: Key-value pair validation and formatting

#### SshKey Model (`app/models/ssh_key.rb`)
- **Key Management**: RSA/ED25519 SSH key storage and validation
- **Server Deployment**: Automatic key deployment to multiple servers
- **Security**: Fingerprint generation and validation

### Background Jobs

#### DeploymentJob (`app/jobs/deployment_job.rb`)
- **Repository Cloning**: Automated git clone and branch checkout
- **Dokku Deployment**: Push to Dokku with real-time logging
- **Status Tracking**: Deployment progress and outcome monitoring
- **Error Handling**: Comprehensive error capture and reporting

#### ApplicationHealthCheckJob
- **Health Monitoring**: Periodic application and server health checks
- **Status Updates**: Real-time health status updates
- **Alerting**: Configurable health alerts and notifications

### Key Controllers

#### ApplicationController (`app/controllers/application_controller.rb`)
- **Base Authentication**: Devise integration with Pundit authorization
- **Global Concerns**: Toastable and activity tracking
- **Parameter Sanitization**: Secure parameter handling

#### Admin Controllers (`app/controllers/admin/`)
- **Dashboard**: System statistics and overview
- **User Management**: Advanced user administration
- **Settings Management**: SMTP, OAuth, and general settings
- **Activity Logs**: Comprehensive activity monitoring

#### Authentication Controllers
- **Custom Sessions**: Enhanced login/logout with activity tracking
- **Custom Registrations**: Profile management and theme preferences
- **OAuth Callbacks**: Google OAuth integration with error handling

### Advanced Features

#### Dark Mode System (`app/assets/stylesheets/dark_mode.css`)
- **CSS Custom Properties**: Comprehensive theming variables
- **Component Coverage**: All Bootstrap components styled for dark mode
- **Smooth Transitions**: Animated theme switching
- **System Integration**: Respects OS dark/light preference
- **Print Optimization**: Light mode for printing

#### Theme Controller (`app/javascript/controllers/theme_controller.js`)
- **Three-State Toggle**: Light, Dark, Auto modes
- **Local Storage**: Theme preference persistence
- **System Listener**: Automatic theme switching based on OS changes
- **Server Sync**: Synchronized with user preferences in database
- **Meta Tag Updates**: Mobile browser theme-color support

#### Toast System (`app/javascript/controllers/toast_controller.js`)
- **Multiple Types**: Success, error, warning, info notifications
- **Auto-positioning**: Smart container management
- **Entrance Animations**: Smooth slide-in effects
- **MDB Integration**: Bootstrap Material Design styling
- **Global API**: JavaScript methods for programmatic use

#### Activity Tracking (`app/controllers/concerns/activity_trackable.rb`)
- **Automatic Logging**: Seamless integration with controller actions
- **Predefined Actions**: Common activity types with consistent formatting
- **Sensitive Data Filtering**: Automatic removal of passwords and secrets
- **Contextual Information**: Request details, IP addresses, and user agents

## 🎨 Styling & UI

### MDBootstrap Integration
- **CDN Delivery**: Fast, reliable asset delivery
- **Material Design**: Modern, intuitive interface components
- **Responsive Grid**: Mobile-first design approach
- **Rich Components**: Comprehensive UI component library

### Custom Styling
- **Dark Mode Variables**: Comprehensive CSS custom property system
- **Component Enhancements**: Enhanced Bootstrap components
- **Smooth Animations**: Transitions and interactive elements
- **Mobile Optimization**: Touch-friendly interface design

### Theme System
- **Three Themes**: Light, Dark, and Auto (system-based)
- **Persistent Preferences**: User and browser-level storage
- **Smooth Transitions**: All elements animated during theme changes
- **Component Coverage**: Every UI element properly themed

## 📱 Responsive Design

### Breakpoints
- **Mobile**: < 768px - Touch-optimized interface
- **Tablet**: 768px - 1024px - Adaptive layout
- **Desktop**: > 1024px - Full-featured interface

### Features
- **Touch-friendly**: Appropriately sized touch targets
- **Responsive Navigation**: Collapsible mobile menu
- **Adaptive Forms**: Mobile-optimized form layouts
- **Flexible Tables**: Responsive table designs

## 🔒 Security Features

### Authentication Security
- **Devise Defaults**: Industry-standard authentication
- **Password Requirements**: Configurable password strength
- **Session Management**: Secure session handling
- **CSRF Protection**: Cross-site request forgery protection

### Authorization
- **Policy-based**: Pundit authorization with resource policies
- **Role Hierarchy**: Admin, Moderator, Registered user roles
- **Resource Permissions**: Granular access control
- **Admin Protection**: Secure admin area access

### Data Protection
- **Activity Logging**: Complete audit trail
- **Secure Uploads**: File validation and size limits
- **Parameter Filtering**: Sensitive data exclusion from logs
- **SQL Injection Prevention**: Parameterized queries

## 🚀 Development

### Code Organization
```
app/
├── controllers/
│   ├── admin/              # Admin interface controllers
│   ├── concerns/           # Shared controller logic (ActivityTrackable, Toastable)
│   └── users/              # User-specific controllers (OAuth)
├── models/
│   └── concerns/           # Shared model logic
├── views/
│   ├── admin/              # Admin interface views
│   ├── devise/             # Authentication views
│   └── layouts/            # Application layouts
├── javascript/
│   └── controllers/        # Stimulus controllers (theme, toast)
└── assets/
    └── stylesheets/        # CSS and dark mode styling
```

### Key Concerns
- **ActivityTrackable** (`app/controllers/concerns/activity_trackable.rb`): Adds comprehensive activity logging to controllers
- **Toastable** (`app/controllers/concerns/toastable.rb`): Enhanced flash message handling with beautiful toasts

### Development Tools
- **Better Errors**: Enhanced error pages with debugging info
- **Letter Opener**: Preview emails in browser during development
- **Rubocop Rails**: Code style and quality enforcement
- **Brakeman**: Security vulnerability scanning

## 🧪 Testing Philosophy

This boilerplate follows a "test in production" approach with comprehensive monitoring:
- **Real-time Activity Logging**: Complete audit trail of user actions
- **Admin Dashboard**: Live system monitoring and statistics
- **Error Handling**: Graceful error management with user feedback
- **Security Monitoring**: Automatic tracking of security-related events

## 📊 Monitoring & Analytics

### Built-in Monitoring
- **Activity Dashboard**: Real-time user activity tracking
- **System Statistics**: User counts, role distribution, recent signups
- **Security Events**: Login attempts, role changes, admin access
- **Performance Metrics**: System health and usage patterns

### Activity Log Features
- **Detailed Tracking**: IP addresses, user agents, timestamps
- **Categorized Actions**: Login, profile updates, admin actions, role changes
- **Search & Filter**: Advanced filtering by user, action type, date range
- **Export Capability**: Data export for external analysis

## 🔧 Customization

### Adding New Roles
```ruby
# Add to db/seeds.rb
Role.find_or_create_by!(name: 'your_role_name')

# Use in models
user.add_role(:your_role_name)
user.has_role?(:your_role_name)

# Use in controllers
before_action :ensure_your_role

private

def ensure_your_role
  redirect_to root_path unless current_user&.has_role?(:your_role_name)
end
```

### Adding New Activity Types
```ruby
# Add to ActivityLog::ACTIONS
new_action: 'new_action'

# Use in controllers
log_activity(ActivityLog::ACTIONS[:new_action], 
            details: "Description of the action")
```

### Custom Toast Types
```ruby
# In controllers
def toast_custom(message, title: nil)
  flash[:custom] = message
  flash[:custom_title] = title if title
end

# Update toast_controller.js to handle new type
```

## 🌍 Deployment

### Production Deployment Guide

Vantage Dokku has specific requirements that make deployment a bit tricky. Follow this guide carefully:

#### Step 1: Prepare Environment Variables
```bash
# Critical: Generate encryption keys first
rails db:encryption:init

# Set these in your production environment:
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=<generated_key>
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=<generated_key>
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=<generated_salt>

# Email configuration (recommended via ENV)
USE_REAL_EMAIL=true
SMTP_ADDRESS=email-smtp.region.amazonaws.com
# ... other SMTP variables
```

#### Step 2: Deploy and Migrate
```bash
# Deploy your application (Dokku example)
git push dokku main

# Run migrations (includes SolidQueue tables)
dokku run your-app rails db:migrate

# Seed admin user
dokku run your-app rails db:seed
```

#### Step 3: Verify Setup
- [ ] Admin login works (`admin@vantage.com` / `password123`)
- [ ] Can create servers and test SSH connections  
- [ ] Can link GitHub accounts
- [ ] Background jobs are processing (check Admin → Activity Logs)
- [ ] Email notifications work (test via Admin → SMTP Settings)

### Deployment Checklist
- [ ] **Encryption keys configured** (Critical!)
- [ ] **Database migrations run** (Including SolidQueue tables)
- [ ] **SMTP environment variables set**
- [ ] **Google OAuth production credentials**
- [ ] **SSL/TLS enabled**
- [ ] **Admin user seeded**
- [ ] **Background job processing verified**

### Recommended Hosting
- **Heroku**: Easy deployment with proper environment variable support
- **DigitalOcean App Platform**: Good for Rails apps with background jobs
- **Railway**: Simple deployment with PostgreSQL included
- **Dokku**: Self-hosted (ironically, manage Dokku with Vantage Dokku!)
- **AWS/GCP**: For enterprise deployments

### Background Job Processing
Vantage Dokku requires background job processing for deployments:
- **SolidQueue**: Default Rails 8 job processor (included)
- **Production**: Ensure job processing is running
- **Monitoring**: Check Admin panel for job status

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines
- Follow Rails conventions and best practices
- Maintain comprehensive activity logging for new features
- Ensure dark mode compatibility for UI changes
- Add appropriate toast notifications for user actions
- Update admin panel for new administrative features

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- **Rails Team** - For Rails 8 and SolidQueue background processing
- **Dokku Team** - For the amazing platform-as-a-service solution
- **GitHub** - For the excellent API and OAuth integration
- **MDBootstrap** - For the beautiful Material Design components
- **Devise & Pundit Teams** - For authentication and authorization frameworks
- **Open Source Community** - For the incredible ecosystem that makes this possible

## 🆘 Support & Troubleshooting

### Common Issues

**GitHub Account Linking Fails in Production**
- Ensure Active Record encryption keys are configured
- Check that the GitHub token has correct permissions (`repo`, `read:user`)

**Background Deployments Not Working**
- Verify SolidQueue tables exist: `rails db:migrate`
- Check if background job processing is running
- Review deployment logs in Admin → Activity Logs

**SMTP Configuration Issues**
- Use environment variables instead of Admin panel for production
- Ensure `USE_REAL_EMAIL=true` in production
- Test email functionality via Admin → SMTP Settings

**Server Connection Failures**
- Verify SSH key permissions and server access
- Check that Dokku is properly installed on target servers
- Test connectivity via Server → Test Connection

### Getting Help
- Check the Admin panel for system status and logs
- Review Activity Logs for detailed error information
- Open an issue on GitHub for bugs or feature requests

---

**Built with ❤️ using Rails 8 - A complete Dokku management platform**

### Quick Navigation
- **Dashboard**: `/dashboard` - Main interface for managing servers and deployments
- **Servers**: `/servers` - Add and manage your Dokku servers
- **Deployments**: `/deployments` - Create and deploy applications
- **Linked Accounts**: `/linked_accounts` - Connect GitHub for private repository access
- **Admin Panel**: `/admin` - System administration (admin only)

### Default Credentials
- **Admin**: `admin@example.com` / `password123`
- **Change immediately after first login!**

## 📸 Credits

### Images
- **Navigation Background**: Photo by [Ray Chan](https://unsplash.com/@wx1993) on [Unsplash](https://unsplash.com/photos/black-flat-screen-computer-monitor-jrNY1BZhnJg)
  - Used under [Unsplash License](https://unsplash.com/license) with modifications (overlay and scaling)
