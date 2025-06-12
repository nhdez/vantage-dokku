Rails.application.routes.draw do
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

  # Public routes
  root "home#index"
  
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
