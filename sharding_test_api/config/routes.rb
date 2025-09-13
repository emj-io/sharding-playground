Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # API routes
  namespace :api do
    namespace :v1 do
      # Single-tenant routes (organization-scoped)
      resources :organizations, only: [] do
        resources :users, only: [:index, :show, :create, :update, :destroy]
        resources :projects, only: [:index, :show, :create, :update, :destroy] do
          resources :tasks, only: [:index, :show, :create, :update, :destroy]
        end
        # Direct task access within organization
        resources :tasks, only: [:index, :show, :create, :update, :destroy]
      end

      # Cross-tenant admin routes
      namespace :admin do
        resources :organizations, only: [:index, :show]
        resources :audit_logs, only: [:index, :show]
        resources :feature_usage, only: [:index]
      end
    end
  end
end