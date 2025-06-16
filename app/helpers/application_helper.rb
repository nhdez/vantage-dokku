module ApplicationHelper
  include Pagy::Frontend

  def breadcrumb
    @breadcrumb ||= []
  end

  def add_breadcrumb(name, path = nil, options = {})
    breadcrumb << {
      name: name,
      path: path,
      options: options,
      icon: options[:icon]
    }
  end

  def render_breadcrumbs
    return '' if breadcrumb.empty?

    content_tag :nav, class: 'mb-3', 'aria-label': 'breadcrumb' do
      content_tag :ol, class: 'breadcrumb bg-light px-3 py-2 rounded' do
        breadcrumb_items = breadcrumb.map.with_index do |crumb, index|
          is_last = index == breadcrumb.size - 1
          
          content_tag :li, class: "breadcrumb-item #{'active fw-semibold' if is_last}", 
                          'aria-current': (is_last ? 'page' : nil) do
            if is_last || crumb[:path].nil?
              content_tag :span, crumb[:name], class: 'text-dark'
            else
              link_to crumb[:path], class: 'text-decoration-none text-primary' do
                content = ''
                content += content_tag(:i, '', class: 'fas fa-home me-1') if index == 0 && crumb[:icon].nil?
                content += content_tag(:i, '', class: "#{crumb[:icon]} me-1") if crumb[:icon]
                content += crumb[:name]
                content.html_safe
              end
            end
          end
        end
        
        safe_join(breadcrumb_items)
      end
    end
  end

  def set_page_breadcrumbs
    # This method will be called in views to set up page-specific breadcrumbs
    controller_path_parts = controller_path.split('/')
    base_controller = controller_path_parts.last
    namespace = controller_path_parts.first if controller_path_parts.length > 1
    
    case base_controller
    when 'dashboard'
      add_breadcrumb 'Dashboard', dashboard_path, icon: 'fas fa-tachometer-alt'
    when 'deployments'
      add_breadcrumb 'Dashboard', dashboard_path
      add_breadcrumb 'Deployments', deployments_path, icon: 'fas fa-rocket'
      
      if action_name == 'show' && @deployment
        add_breadcrumb @deployment.name, deployment_path(@deployment)
      elsif action_name == 'new'
        add_breadcrumb 'New Deployment'
      elsif action_name == 'edit' && @deployment
        add_breadcrumb @deployment.name, deployment_path(@deployment)
        add_breadcrumb 'Edit'
      elsif action_name == 'configure_domain' && @deployment
        add_breadcrumb @deployment.name, deployment_path(@deployment)
        add_breadcrumb 'Domain Configuration'
      elsif action_name == 'attach_ssh_keys' && @deployment
        add_breadcrumb @deployment.name, deployment_path(@deployment)
        add_breadcrumb 'SSH Keys'
      elsif action_name == 'manage_environment' && @deployment
        add_breadcrumb @deployment.name, deployment_path(@deployment)
        add_breadcrumb 'Environment Variables'
      elsif action_name == 'configure_databases' && @deployment
        add_breadcrumb @deployment.name, deployment_path(@deployment)
        add_breadcrumb 'Database Configuration'
      elsif action_name == 'git_configuration' && @deployment
        add_breadcrumb @deployment.name, deployment_path(@deployment)
        add_breadcrumb 'Git Configuration', nil, icon: 'fab fa-git-alt'
      elsif action_name == 'logs' && @deployment
        add_breadcrumb @deployment.name, deployment_path(@deployment)
        add_breadcrumb 'Deployment Logs', nil, icon: 'fas fa-terminal'
      end
    when 'servers'
      add_breadcrumb 'Dashboard', dashboard_path
      add_breadcrumb 'Servers', servers_path, icon: 'fas fa-server'
      
      if action_name == 'show' && @server
        add_breadcrumb @server.name, server_path(@server)
      elsif action_name == 'new'
        add_breadcrumb 'New Server'
      elsif action_name == 'edit' && @server
        add_breadcrumb @server.name, server_path(@server)
        add_breadcrumb 'Edit'
      elsif action_name == 'logs' && @server
        add_breadcrumb @server.name, server_path(@server)
        add_breadcrumb 'Activity Logs'
      end
    when 'ssh_keys'
      add_breadcrumb 'Dashboard', dashboard_path
      add_breadcrumb 'SSH Keys', ssh_keys_path, icon: 'fas fa-key'
      
      if action_name == 'show' && @ssh_key
        add_breadcrumb @ssh_key.name
      elsif action_name == 'new'
        add_breadcrumb 'New SSH Key'
      elsif action_name == 'edit' && @ssh_key
        add_breadcrumb @ssh_key.name, ssh_key_path(@ssh_key)
        add_breadcrumb 'Edit'
      end
    when 'linked_accounts'
      add_breadcrumb 'Dashboard', dashboard_path
      add_breadcrumb 'Linked Accounts', linked_accounts_path, icon: 'fas fa-link'
      
      if action_name == 'show' && @linked_account
        add_breadcrumb @linked_account.display_name
      elsif action_name == 'new'
        add_breadcrumb 'Link New Account'
      elsif action_name == 'edit' && @linked_account
        add_breadcrumb @linked_account.display_name, linked_account_path(@linked_account)
        add_breadcrumb 'Edit'
      end
    when 'registrations'
      add_breadcrumb 'Dashboard', dashboard_path
      add_breadcrumb 'Account Settings', edit_user_registration_path, icon: 'fas fa-user-cog'
    when 'dashboard'
      if namespace == 'admin'
        add_breadcrumb 'Dashboard', dashboard_path
        add_breadcrumb 'Admin', admin_root_path
        
        case action_name
        when 'general_settings'
          add_breadcrumb 'General Settings'
        when 'smtp_settings'
          add_breadcrumb 'SMTP Settings'
        when 'oauth_settings'
          add_breadcrumb 'OAuth Settings'
        end
      end
    when 'users'
      if namespace == 'admin'
        add_breadcrumb 'Dashboard', dashboard_path
        add_breadcrumb 'Admin', admin_root_path
        add_breadcrumb 'Users', admin_users_path
        
        if action_name == 'show' && @user
          add_breadcrumb @user.full_name
        elsif action_name == 'edit' && @user
          add_breadcrumb @user.full_name, admin_user_path(@user)
          add_breadcrumb 'Edit'
        end
      end
    when 'activity_logs'
      if namespace == 'admin'
        add_breadcrumb 'Dashboard', dashboard_path
        add_breadcrumb 'Admin', admin_root_path
        add_breadcrumb 'Activity Logs', admin_activity_logs_path
        
        if action_name == 'show' && @activity_log
          add_breadcrumb "Activity ##{@activity_log.id}"
        end
      end
    end
  end
end
