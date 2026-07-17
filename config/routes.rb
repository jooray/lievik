Rails.application.routes.draw do
  # Authentication
  get "/auth/nostr", to: "sessions#new", as: :nostr_login
  get "/auth/nostr/poll", to: "sessions#poll", as: :auth_nostr_poll
  get "/auth/nostr/callback", to: "sessions#callback", as: :auth_nostr_callback
  post "/auth/nostr/callback", to: "sessions#callback"
  post "/auth/nostr/refresh_profile", to: "sessions#refresh_profile", as: :refresh_profile
  delete "/logout", to: "sessions#destroy", as: :logout

  # PWA: web app manifest so the app is installable (manifest-only PWA — no
  # service worker; nothing here intercepts navigations).
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest

  # Public landing page
  root "pages#landing"

  # Dashboard
  get "/dashboard", to: "dashboard#index", as: :dashboard
  post "dashboard/rate_all", to: "dashboard#rate_all", as: :rate_all

  # Sources
  resources :sources do
    member do
      post :refresh
    end
    collection do
      post :refresh_all
    end
  end

  # AI Channel Creation
  get "/channels/ai", to: "channel_ai_chat#index", as: :channel_ai_chat
  post "/channels/ai/stream", to: "channel_ai_chat#stream", as: :channel_ai_chat_stream
  post "/channels/ai/bulk_create", to: "channel_ai_chat#bulk_create", as: :channel_ai_bulk_create

  # Channels
  resources :channels do
    member do
      post :bulk_mark_used, controller: "channel_events"
      post :bulk_rate, controller: "channel_events"
      get :settings
      patch :update_settings
      post :rate
    end
    resources :events, only: [:index, :show], controller: "channel_events" do
      member do
        post :mark_used
        post :mark_unused
      end
    end
    resources :contents, controller: "channel_contents" do
      member do
        post :generate
        get :generate_stream
        post :refine
        get :refine_stream
        post :publish
        post :revert
      end
    end
  end

  # Manual events
  resources :manual_events, only: [:new, :create]

  # Events (all events view)
  resources :events, only: [:index, :show] do
    collection do
      post :bulk_rate
    end
    member do
      post :bulk_mark_used
    end
  end

  # Activity logs
  resources :activity_logs do
    member do
      get :dev_logs
      post :cancel
      post :retry_job
    end
    collection do
      get :active
      get :all_dev_logs
      post :cleanup_stale
    end
  end

  # User settings
  get "/user/edit", to: "users#edit", as: :edit_user
  patch "/user", to: "users#update", as: :user
  post "/user/templates/add", to: "users#add_template", as: :add_user_template
  patch "/user/templates/update", to: "users#update_template", as: :update_user_template
  delete "/user/templates/delete", to: "users#delete_template", as: :delete_user_template
  post "/user/reindex", to: "users#reindex", as: :reindex_user

  # RAG Chat
  get "/chat", to: "rag_chat#index", as: :rag_chat
  post "/chat/ask", to: "rag_chat#ask", as: :rag_chat_ask
  post "/chat/ask_stream", to: "rag_chat#ask_stream", as: :rag_chat_ask_stream

  # API tokens
  resources :api_tokens, only: [:create, :destroy]

  # MCP (Model Context Protocol) endpoint — auth via Authorization: Bearer <api token>
  post "/mcp", to: "mcp/server#handle"

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
