Rails.application.routes.draw do
  # The apex whatstatus.info (whatstatus.localhost in development) only serves the old WhatStatus page.
  constraints(host: /\Awhatstatus\.(info|localhost)\z/) do
    root "whatstatus#show", as: :whatstatus_root
  end
  root "landings#show"

  resource :first_run, only: %i[show create]
  resource :session, only: %i[new create destroy]
  unless Rails.application.config.x.single_user_mode
    get "join" => "joins#new", as: :new_join
    get "join/:code" => "joins#show", as: :join
    post "join/:code" => "joins#create"
    scope "join/:code", as: :join, module: :joins do
      resource :profile, only: %i[create destroy]
      resource :check, only: :create
    end
    # Members put this link on their tracker profile to opt in. It only explains itself.
    get "opt-in/:code" => "opt_ins#show", as: :opt_in
  end
  resource :password, only: %i[edit update]
  resource :privacy, only: :show, controller: "privacy"

  namespace :onboarding do
    resource :welcome, only: %i[show update]
    resource :preferences, only: %i[show update]
    resource :completion, only: %i[show create]
  end

  resource :tracker_selection, only: %i[show update], path: "trackers/add"
  scope "trackers/add/:site_slug", as: :site do
    resource :connection, only: %i[new create], path: "", module: :sites
    scope module: :sites do
      resource :profile, only: %i[create destroy]
      resource :check, only: :create
    end
  end

  resource :dashboard, only: :show
  resource :refresh, only: :create
  resources :dismissals, only: :create
  resources :connections, only: :show, path: "trackers" do
    resource :history, only: :show, module: :connections
    resource :manual_snapshot, only: :create, module: :connections
  end
  resource :comparison, only: :show, path: "compare" do
    resources :pins, only: %i[create destroy], module: :comparisons
  end

  namespace :settings do
    root to: redirect("/settings/trackers")
    resource :tracker_order, only: :update
    resources :connections, only: %i[index show destroy], path: "trackers" do
      scope module: :connections do
        resource :key, only: %i[edit update]
        resource :color, only: :update
        resource :pause, only: %i[create destroy]
        resource :poll, only: :create
        resource :check, only: :create
      end
    end
    resources :qui_connections, only: %i[index create update destroy], path: "qui" do
      post :poll, on: :collection
    end
    resource :preferences, only: %i[edit update]
    resource :developer, only: :show, controller: "developer" do
      resource :metrics_token, only: %i[create destroy]
    end
    resources :invites, only: %i[index create destroy], param: :code unless Rails.application.config.x.single_user_mode
    resource :account, only: %i[show destroy]
    resources :sessions, only: :destroy
    resource :other_sessions, only: :destroy
    resource :data, only: :show, controller: "data"
    resource :export, only: :show
    resource :import, only: :create
  end

  namespace :admin do
    root to: redirect(Rails.application.config.x.single_user_mode ? "/admin/sites" : "/admin/users")
    resources :setup_skips, only: :create
    unless Rails.application.config.x.single_user_mode
      resources :users, only: %i[index show update] do
        scope module: :users do
          resource :password_reset, only: :create
          resource :disable, only: %i[create destroy]
          resource :branch_disable, only: :create
          resources :grants, only: %i[create destroy], param: :slug
          resources :integration_grants, only: %i[create destroy], param: :slug
        end
      end
      resources :invites, only: %i[index create destroy], param: :code
    end
    resources :sites, only: %i[index show update], param: :slug do
      scope module: :sites do
        resource :setup, only: %i[new create]
        resource :pause, only: %i[create destroy]
      end
    end
    resource :settings, only: %i[show update]
    resources :integrations, only: :update, param: :slug
  end

  mount MissionControl::Jobs::Engine, at: "/jobs"

  if Rails.env.development?
    get "dev/session" => "dev/sessions#show"
  end

  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Each user's own stats for their Prometheus. The bearer token says whose, so the path has no id.
  namespace :users do
    resource :metrics, only: :show
  end

  # Sherlock's own metrics, for our Prometheus on the private network. Anyone else gets a 404.
  # Checks the direct peer, not request.ip, and refuses anything that came through the public proxy,
  # so a proxy that forwards from a private address can't open it up.
  constraints(->(request) {
    request.headers["X-Forwarded-For"].blank? && IPAddr.new(request.remote_addr).then { _1.private? || _1.loopback? }
  }) do
    mount Yabeda::Prometheus::Exporter => "/metrics"
  end
end
