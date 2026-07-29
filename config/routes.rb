Rails.application.routes.draw do
  resource  :session
  resource  :registration, only: %i[ new create ]
  resources :passwords, param: :token

  # Admin panel
  namespace :admin do
    resources :users do
      member do
        post :invite
        patch :update_password
      end
    end
    namespace :youtube do
      get    "connect",    to: "auth#connect",    as: :connect
      get    "callback",   to: "auth#callback",   as: :callback
      delete "disconnect", to: "auth#disconnect", as: :disconnect
    end
    namespace :tiktok do
      get    "connect",       to: "auth#connect",       as: :connect
      get    "callback",      to: "auth#callback",      as: :callback
      post   "refresh_token", to: "auth#refresh_token", as: :refresh_token
      delete "disconnect",    to: "auth#disconnect",    as: :disconnect
    end
    namespace :instagram do
      get    "connect",        to: "auth#connect",        as: :connect
      get    "callback",       to: "auth#callback",       as: :callback
      post   "select_account", to: "auth#select_account", as: :select_account
      post   "refresh_token",  to: "auth#refresh_token",  as: :refresh_token
      delete "disconnect",     to: "auth#disconnect",     as: :disconnect
    end
  end

  # Model index pages
  resources :users,            only: [ :index, :show, :edit, :update ]
  resources :media_assets,     only: [ :index, :show, :edit, :update ]
  resources :planned_posts,    only: [ :index, :show, :edit, :update ] do
    member do
      post :publish
      post :verify
    end
    collection do
      patch :bulk_reschedule
      delete :bulk_destroy
    end
  end
  resources :social_templates, only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
  resources :known_people,     only: [ :index, :show, :new, :create, :edit, :update, :destroy ]
  resources :insights,         only: [ :index, :show ]
  get "llm_costs", to: "llm_costs#index", as: :llm_costs
  resources :sessions,         only: [ :index ]

  # LLM chat
  get    "chat",          to: "chats#chat",           as: :chat
  post   "chat/messages", to: "chats#create_message", as: :chat_messages
  post   "chat/model",    to: "chats#select_model",   as: :chat_model
  delete "chat",          to: "chats#destroy",        as: :destroy_chat

  # Public legal pages — must stay reachable without authentication because
  # Meta, Google and TikTok fetch them during app review.
  get "tos",     to: "pages#tos",     as: :tos
  get "privacy", to: "pages#privacy", as: :privacy

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # API endpoints
  namespace :api do
    resources :planned_posts, only: [ :index, :show, :create, :update, :destroy ] do
      collection do
        post :bulk_create
      end
    end
    resources :media_assets, only: [ :index, :show ]
  end

  # Defines the root path route ("/")
  root to: "users#index"

   # Mission Control
   mount MissionControl::Jobs::Engine, at: "/jobs"
end
