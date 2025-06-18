Rails.application.routes.draw do
  # Mount ActionCable
  mount ActionCable.server => '/cable'
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
      get :attach_ssh_keys
      post :update_ssh_keys
      get :manage_environment
      post :update_environment
      get :configure_databases
      post :update_database_configuration
      delete :delete_database_configuration
      post :create_dokku_app
      post :check_ssl_status
      get :execute_commands
      post :run_command
      get :server_logs
      post :start_log_streaming
      post :stop_log_streaming
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
    resources :activity_logs, only: [:index, :show]
    get "general_settings", to: "dashboard#general_settings"
    patch "general_settings", to: "dashboard#update_general_settings"
    post "regenerate_ssh_keys", to: "dashboard#regenerate_ssh_keys"
    get "smtp_settings", to: "dashboard#smtp_settings"
    patch "smtp_settings", to: "dashboard#update_smtp_settings"
    post "test_email", to: "dashboard#test_email"
    get "oauth_settings", to: "dashboard#oauth_settings"
    patch "oauth_settings", to: "dashboard#update_oauth_settings"
    resources :users, only: [:index, :show, :edit, :update] do
      member do
        patch :assign_role
        delete :remove_role
      end
    end
  end
  devise_for :users, controllers: {
    sessions: 'sessions',
    registrations: 'registrations',
    omniauth_callbacks: 'users/omniauth_callbacks'
  }

  # Public routes - redirect to login
  root to: redirect('/users/sign_in')
  
  # Authenticated user routes
  authenticated :user do
    root "dashboard#index", as: :authenticated_root
  end
  
  # Dashboard and app routes
  get "dashboard", to: "dashboard#index"
  get "projects", to: "dashboard#projects"
  get "analytics", to: "dashboard#analytics"
  get "settings", to: "dashboard#settings"

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
