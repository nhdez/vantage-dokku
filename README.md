# Vantage - Rails 8 Boilerplate

[![Rails Version](https://img.shields.io/badge/rails-8.0.2-red.svg)](https://rubyonrails.org/)
[![Ruby Version](https://img.shields.io/badge/ruby-3.2+-red.svg)](https://www.ruby-lang.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

![vantage_bp](https://github.com/user-attachments/assets/68761cc4-89f7-42f7-bc82-5b8a3cadb7b0)

A modern, production-ready Rails 8 boilerplate application featuring comprehensive authentication, advanced dark mode theming, beautiful toast notifications, detailed activity logging, and a powerful admin panel. Built with MDBootstrap Material Design for an exceptional user experience.

## ✨ Features

### 🔐 Authentication & Authorization
- **Devise Authentication** - Complete user management with sign-up, sign-in, password recovery
- **Google OAuth Integration** - One-click sign-in with Google accounts
- **Role-Based Access Control** - Powered by Rolify with three default roles (Admin, Moderator, Registered)
- **Pundit Authorization** - Policy-based access control for granular permissions
- **Profile Management** - User profiles with picture uploads and customizable themes
- **Activity Logging** - Comprehensive tracking of all user actions and admin operations

### 🎨 Modern UI & Theming
- **MDBootstrap Material Design** - Beautiful, responsive Material Design components
- **Advanced Dark Mode** - System-aware theme switching with manual override options
- **Intelligent Theme Toggle** - Three-state toggle (Light/Dark/Auto) with persistence
- **CSS Custom Properties** - Comprehensive theming system with smooth transitions
- **Responsive Design** - Mobile-first approach optimized for all device sizes
- **Custom Animations** - Smooth transitions and interactive elements

### 🛡️ Admin Panel
- **Comprehensive Dashboard** - Real-time statistics and system overview
- **User Management** - Advanced search, filtering, and role assignment
- **SMTP Configuration** - Dynamic email settings with AWS SES support and test functionality
- **OAuth Settings** - Google OAuth credential management with enable/disable controls
- **General Settings** - Application-wide configuration management
- **Activity Monitoring** - Real-time activity logs with detailed filtering and search

### 📢 Toast Notification System
- **Beautiful Notifications** - Animated toast messages with multiple types (success, error, warning, info)
- **Smart Positioning** - Top-right positioning with auto-stacking
- **Auto-dismiss** - Configurable timing and manual dismissal
- **Dark Mode Support** - Seamless integration with theme system
- **Backend Integration** - Easy-to-use helper methods for controllers

### 🔍 Activity & Security Features
- **Detailed Activity Logging** - IP tracking, user agent detection, and action timestamps
- **Security Monitoring** - Login attempts, role changes, and admin access tracking
- **Search & Filtering** - Advanced filtering of activity logs by user, action, and date range
- **Data Protection** - Sensitive parameter filtering and secure credential storage

## 🚀 Quick Start

### Prerequisites
- Ruby 3.2+
- Rails 8.0.2
- PostgreSQL
- Node.js (for asset pipeline)

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd vantage
   ```

2. **Install dependencies**
   ```bash
   bundle install
   ```

3. **Database setup**
   ```bash
   rails db:create
   rails db:migrate
   rails db:seed
   ```

4. **Start the server**
   ```bash
   rails server
   ```

5. **Access the application**
   - Application: http://localhost:3000
   - Admin login: `admin@vantage.com` / `password123`

## ⚙️ Configuration

### Environment Variables

Create a `.env` file in the root directory:

```env
# Database
DATABASE_URL=postgresql://username:password@localhost/vantage_development

# Google OAuth (Configure via Admin Panel)
GOOGLE_CLIENT_ID=your_google_client_id
GOOGLE_CLIENT_SECRET=your_google_client_secret

# SMTP (Configure via Admin Panel)
SMTP_ADDRESS=email-smtp.region.amazonaws.com
SMTP_USERNAME=your_smtp_username
SMTP_PASSWORD=your_smtp_password
```

### Google OAuth Setup

1. Visit [Google Cloud Console](https://console.cloud.google.com)
2. Create a new project or select existing
3. Enable Google+ API
4. Create OAuth 2.0 credentials
5. Add authorized redirect URI: `http://localhost:3000/users/auth/google_oauth2/callback`
6. Configure credentials in Admin → OAuth Settings

### SMTP Configuration

Configure email delivery through Admin → SMTP Settings:
- Supports AWS SES, Gmail, and custom SMTP providers
- Built-in test email functionality
- Secure credential storage
- Dynamic configuration updates

## 🏗️ Architecture

### Core Models

#### User Model (`app/models/user.rb`)
- **Authentication**: Devise modules with OAuth integration
- **Roles**: Rolify integration with helper methods (`admin?`, `moderator?`)
- **Profiles**: Profile picture uploads with validation
- **Themes**: Personal theme preferences (light/dark/auto)
- **OAuth**: Google OAuth integration with account linking

#### Role Model (`app/models/role.rb`)
- **Rolify Integration**: Dynamic role assignment and checking
- **Resource Scoping**: Support for resource-specific roles
- **Database Relations**: Many-to-many with users

#### ActivityLog Model (`app/models/activity_log.rb`)
- **Comprehensive Tracking**: User actions, IP addresses, user agents
- **Categorized Actions**: Predefined action types with custom details
- **Search & Filtering**: Scopes for date ranges, users, and actions
- **Browser Detection**: Simple user agent parsing

#### AppSetting Model (`app/models/app_setting.rb`)
- **Typed Values**: String, boolean, and integer settings
- **Dynamic Configuration**: Runtime application configuration
- **Default Management**: Automatic setup of default settings

#### OauthSetting Model (`app/models/oauth_setting.rb`)
- **Provider Management**: OAuth provider configuration
- **Dynamic Credentials**: Runtime OAuth setup
- **Enable/Disable**: Toggle OAuth providers on demand

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

### Production Checklist
- [ ] Set strong database passwords
- [ ] Configure production SMTP settings
- [ ] Set up Google OAuth production credentials
- [ ] Enable SSL/TLS
- [ ] Configure error monitoring (Sentry, Bugsnag)
- [ ] Set up database backups
- [ ] Configure proper log rotation
- [ ] Set up monitoring and alerting

### Recommended Stack
- **Hosting**: Heroku, Railway, Digital Ocean, or AWS
- **Database**: PostgreSQL (production)
- **Email**: AWS SES, SendGrid, or Mailgun
- **Monitoring**: Sentry for error tracking
- **Analytics**: Google Analytics
- **Performance**: New Relic or Datadog

### Environment Configuration
```ruby
# config/environments/production.rb
config.force_ssl = true
config.log_level = :info
config.cache_classes = true
config.eager_load = true
```

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

- **Rails Team** - For the incredible Rails 8 framework
- **MDBootstrap** - For the beautiful Material Design components
- **Devise Team** - For the robust authentication framework
- **Pundit** - For the elegant authorization system
- **Rolify** - For the flexible role management
- **Open Source Community** - For the amazing gem ecosystem

## 🆘 Support

For support, questions, or feature requests:
- Open an issue on GitHub
- Check the comprehensive admin interface for debugging
- Review activity logs for troubleshooting
- Consult the built-in documentation in admin settings

---

**Built with ❤️ using Rails 8 and modern web technologies**

### Quick Links
- **Dashboard**: `/dashboard` (authenticated users)
- **Admin Panel**: `/admin` (admin users only)
- **User Settings**: `/users/edit` (profile management)
- **Toast Demo**: `/toast_demo` (see toast system in action)

### Default Credentials
- **Admin**: `admin@vantage.com` / `password123`
