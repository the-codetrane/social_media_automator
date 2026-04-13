Rails.application.routes.draw do
  resource  :session
  resource  :registration, only: %i[ new create ]
  resources :passwords, param: :token

  # Model index pages
  resources :users,            only: [ :index ]
  resources :media_assets,     only: [ :index ]
  resources :planned_posts,    only: [ :index ]
  resources :social_templates, only: [ :index ]
  resources :sessions,         only: [ :index ]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Instagram OAuth
  namespace :instagram do
    get  "connect",        to: "auth#connect",        as: :connect
    get  "callback",       to: "auth#callback",        as: :callback
    post "select_account", to: "auth#select_account",  as: :select_account
  end

  # Defines the root path route ("/")
  root to: "users#index"
end
