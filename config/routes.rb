Rails.application.routes.draw do
  # PWA routes (must come early to prevent routing conflicts)
  get "service-worker" => "pwa#service_worker", as: :pwa_service_worker
  get "manifest" => "pwa#manifest", as: :pwa_manifest

  # Mount ActionCable
  mount ActionCable.server => "/cable"
  resources :linked_accounts do
    member do
      post :test_connection
    end
  end
  resources :deployments, param: :uuid do
    member do
      # DeploymentsController — CRUD, deploy, git, logs
      get  :git_configuration
      post :update_git_configuration
      post :deploy
      get  :logs
      post :create_dokku_app

      # Deployments::DomainsController
      get    :configure_domain,   to: "deployments/domains#configure_domain"
      post   :update_domains,     to: "deployments/domains#update_domains"
      delete :delete_domain,      to: "deployments/domains#delete_domain"
      post   :check_ssl_status,   to: "deployments/domains#check_ssl_status"

      # Deployments::SshKeysController
      get  :attach_ssh_keys, to: "deployments/ssh_keys#attach_ssh_keys"
      post :update_ssh_keys, to: "deployments/ssh_keys#update_ssh_keys"

      # Deployments::EnvironmentController
      get  :manage_environment,  to: "deployments/environment#manage_environment"
      post :update_environment,  to: "deployments/environment#update_environment"

      # Deployments::DatabasesController
      get    :configure_databases,              to: "deployments/databases#configure_databases"
      post   :update_database_configuration,    to: "deployments/databases#update_database_configuration"
      delete :delete_database_configuration,    to: "deployments/databases#delete_database_configuration"

      # Deployments::PortsController
      get    :port_mappings,     to: "deployments/ports#port_mappings"
      post   :sync_port_mappings, to: "deployments/ports#sync_port_mappings"
      post   :add_port_mapping,  to: "deployments/ports#add_port_mapping"
      delete :remove_port_mapping, to: "deployments/ports#remove_port_mapping"
      post   :clear_port_mappings, to: "deployments/ports#clear_port_mappings"

      # Deployments::CommandsController
      get  :execute_commands, to: "deployments/commands#execute_commands"
      post :run_command,      to: "deployments/commands#run_command"

      # Deployments::ServerLogsController
      get  :server_logs,          to: "deployments/server_logs#server_logs"
      post :start_log_streaming,  to: "deployments/server_logs#start_log_streaming"
      post :stop_log_streaming,   to: "deployments/server_logs#stop_log_streaming"

      # Deployments::ScansController
      get  :scans,        to: "deployments/scans#scans"
      post :trigger_scan, to: "deployments/scans#trigger_scan"
    end
    resources :vulnerability_scans, only: [ :show ], param: :id do
      member do
        get :fetch_osv_details
      end
      collection do
        get :fetch_all_osv_details
      end
    end
  end
  resources :ssh_keys
  resources :servers, param: :uuid do
    member do
      # ServersController — CRUD, connection, updates, logs
      post :test_connection
      post :update_server
      post :install_dokku
      post :restart_server
      get  :logs

      # Servers::FirewallController
      get    :firewall_rules,       to: "servers/firewall#firewall_rules"
      post   :sync_firewall_rules,  to: "servers/firewall#sync_firewall_rules"
      post   :enable_ufw,           to: "servers/firewall#enable_ufw"
      post   :disable_ufw,          to: "servers/firewall#disable_ufw"
      post   :add_firewall_rule,    to: "servers/firewall#add_firewall_rule"
      delete :remove_firewall_rule, to: "servers/firewall#remove_firewall_rule"
      patch  :toggle_firewall_rule, to: "servers/firewall#toggle_firewall_rule"
      post   :apply_firewall_rules, to: "servers/firewall#apply_firewall_rules"

      # Servers::VulnerabilityController
      get  :vulnerability_scanner, to: "servers/vulnerability#vulnerability_scanner"
      post :check_scanner_status,  to: "servers/vulnerability#check_scanner_status"
      post :install_go,            to: "servers/vulnerability#install_go"
      post :install_osv_scanner,   to: "servers/vulnerability#install_osv_scanner"
      post :update_scan_config,    to: "servers/vulnerability#update_scan_config"
      get  :scan_all_deployments,  to: "servers/vulnerability#scan_all_deployments"
    end
  end
  patch "themes/update", to: "themes#update", as: :update_theme
  get "toast_demo/index"
  get "toast_demo/show_success"
  get "toast_demo/show_error"
  get "toast_demo/show_warning"
  get "toast_demo/show_info"
  get "toast_demo/show_login"
  get "toast_demo/show_role_assigned"
  get "toast_demo/show_settings_updated"
  get "toast_demo/show_multiple"
  namespace :admin do
    root "dashboard#index"
    resources :activity_logs, only: [ :index, :show ]
    get "general_settings", to: "dashboard#general_settings"
    patch "general_settings", to: "dashboard#update_general_settings"

    get "smtp_settings", to: "dashboard#smtp_settings"
    patch "smtp_settings", to: "dashboard#update_smtp_settings"
    post "test_email", to: "dashboard#test_email"
    get "oauth_settings", to: "dashboard#oauth_settings"
    patch "oauth_settings", to: "dashboard#update_oauth_settings"
    resources :users, only: [ :index, :show, :edit, :update ] do
      member do
        patch :assign_role
        delete :remove_role
      end
    end
  end
  devise_for :users, controllers: {
    sessions: "users/sessions",
    registrations: "users/registrations",
    passwords: "users/passwords",
    omniauth_callbacks: "users/omniauth_callbacks"
  }

  # Authenticated user routes (must come first)
  authenticated :user do
    root "dashboard#index", as: :authenticated_root
  end

  # Public routes - redirect to login
  root to: redirect("/users/sign_in")

  get "maintenance", to: "home#maintenance"

  # Dashboard and app routes
  get "dashboard", to: "dashboard#index"
  post "dashboard/trigger_health_checks", to: "dashboard#trigger_health_checks"
  get "oauth_debug", to: "oauth_debug#debug"
  get "test_oauth_redirect", to: redirect("/users/auth/google_oauth2")

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
