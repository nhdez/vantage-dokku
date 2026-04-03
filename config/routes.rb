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
      get :git_configuration
      post :update_git_configuration
      post :deploy
      get :logs
      get :configure_domain
      post :update_domains
      delete :delete_domain
      get :attach_ssh_keys
      post :update_ssh_keys
      get :manage_environment
      post :update_environment
      get :configure_databases
      post :update_database_configuration
      delete :delete_database_configuration
      get :port_mappings
      post :sync_port_mappings
      post :add_port_mapping
      delete :remove_port_mapping
      post :clear_port_mappings
      post :create_dokku_app
      post :check_ssl_status
      get :execute_commands
      post :run_command
      get :server_logs
      post :start_log_streaming
      post :stop_log_streaming
      get :scans
      post :trigger_scan
      # Kamal — Phase 3 (config, registry, env)
      get  :kamal_configuration
      patch :update_kamal_configuration
      get :kamal_registry
      patch :update_kamal_registry
      post :test_kamal_registry
      post :provision_self_hosted_registry
      post :kamal_push_env
      # Kamal — Phase 4 (deploy operations & accessories)
      post :kamal_rollback
      post :kamal_restart
      post :kamal_stop
      post :kamal_start
      get  :kamal_app_details
      get  :kamal_accessories
      post :add_kamal_accessory
      delete :remove_kamal_accessory
      post :boot_kamal_accessory
      post :reboot_kamal_accessory
      # Kamal — Phase 5 (setup & proxy)
      post :kamal_setup
      post :kamal_proxy_reboot
      # Kamal — Phase 6 (preview)
      get  :kamal_config_preview
      get  :download_kamal_config
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
      post :test_connection
      post :update_server
      post :install_dokku
      post :restart_server
      get :logs
      get :firewall_rules
      post :sync_firewall_rules
      post :enable_ufw
      post :disable_ufw
      post :add_firewall_rule
      delete :remove_firewall_rule
      patch :toggle_firewall_rule
      post :apply_firewall_rules
      get :vulnerability_scanner
      post :check_scanner_status
      post :install_go
      post :install_osv_scanner
      post :update_scan_config
      get :scan_all_deployments
      post :check_kamal_prerequisites
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
