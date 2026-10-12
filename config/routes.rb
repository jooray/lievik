Rails.application.routes.draw do
  # Authentication
  get "/auth/nostr", to: "sessions#new", as: :nostr_login
  get "/auth/nostr/poll", to: "sessions#poll", as: :auth_nostr_poll
  get "/auth/nostr/callback", to: "sessions#callback", as: :auth_nostr_callback
  post "/auth/nostr/callback", to: "sessions#callback"
  # bunker:// — the signer-initiated flow, where the user pastes a URI
  # naming their signer instead of the signer scanning ours.
  post "/auth/nostr/bunker", to: "sessions#bunker", as: :auth_nostr_bunker
  post "/auth/nostr/refresh_profile", to: "sessions#refresh_profile", as: :refresh_profile
  delete "/logout", to: "sessions#destroy", as: :logout

  # PWA: manifest, a scope-"/" service worker (assets only — it never
  # intercepts navigations), and the version endpoint the client polls so an
  # open tab or installed app can never keep running a stale build.
  # `defaults: { format: :json }` so the manifest resolves regardless of the
  # client's Accept header — without it an HTML-ish Accept raises MissingTemplate.
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest, defaults: { format: :json }
  get "service_worker.js" => "pwa#service_worker", as: :pwa_service_worker
  get "version.json" => "pwa#version", as: :app_version

  # Public landing page
  root "pages#landing"
  # Localized copies of the landing page (hreflang alternates of "/").
  get "/:locale", to: "pages#landing", as: :localized_landing, constraints: { locale: /en|sk|cs|es/ }

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
    resources :contents, controller: "channel_contents" do
      member do
        # POST, not GET: both mutate the draft (they save a version and
        # overwrite content), and Rails' CSRF protection does not cover GET.
        post :generate_stream
        post :refine_stream
        post :publish
        post :revert
      end
    end
  end

  # Manual events
  resources :manual_events, only: [ :new, :create ]

  # Events (all events view)
  resources :events, only: [ :index, :show ] do
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
  # Paid access on the hosted instance (404 when billing is not configured)
  get "billing", to: "billing#show", as: :billing
  get "billing/app_return", to: "billing_returns#show", as: :billing_app_return
  get "billing/status", to: "billing#status", as: :billing_status
  post "billing/trial", to: "billing#start_trial", as: :billing_trial
  post "billing/charges", to: "billing#create_charge", as: :billing_charges

  get "/chat", to: "rag_chat#index", as: :rag_chat
  post "/chat/ask", to: "rag_chat#ask", as: :rag_chat_ask
  post "/chat/ask_stream", to: "rag_chat#ask_stream", as: :rag_chat_ask_stream

  # API tokens
  resources :api_tokens, only: [ :create, :destroy ]

  # MCP (Model Context Protocol) endpoint — auth via Authorization: Bearer <api token>
  post "/mcp", to: "mcp/server#handle"

  # App API (Android). docs/API_V1.md is the contract; auth via
  # Authorization: Bearer <api token>, except meta and auth.
  namespace :api do
    namespace :v1 do
      get "meta", to: "meta#show"

      post "auth/challenge", to: "auth#challenge"
      post "auth/token", to: "auth#token"
      post "auth/nostrconnect", to: "auth#nostrconnect"
      post "auth/poll", to: "auth#poll"
      delete "session", to: "auth#destroy"
      post "auth/bunker", to: "auth#bunker"

      get "me", to: "me#show"
      patch "me", to: "me#update"
      post "me/refresh_profile", to: "me#refresh_profile"
      post "me/reindex", to: "me#reindex"

      resources :templates, only: [ :index, :create, :update, :destroy ], param: :index
      resources :api_tokens, only: [ :index, :create, :destroy ]

      get "dashboard", to: "dashboard#show"
      post "dashboard/rate_all", to: "dashboard#rate_all"

      get "sync", to: "sync#show"

      resources :sources, except: [ :new, :edit ] do
        member do
          get :events
          post :refresh
        end
        collection do
          post :refresh_all
        end
      end

      # Before `resources :channels`, so "ai" is never taken for a channel id.
      post "channels/ai/stream", to: "channel_ai_chat#stream"
      post "channels/ai/bulk_create", to: "channel_ai_chat#bulk_create"

      resources :channels, except: [ :edit ] do
        member do
          post :rate
        end
        resources :events, controller: "channel_events", only: [ :index ] do
          collection do
            post :mark_used
            post :mark_unused
            post :rate
          end
        end
        resources :contents, controller: "channel_contents", except: [ :new, :edit ] do
          member do
            post :generate
            post :refine
            post :publish
            post :revert
          end
        end
      end

      resources :events, only: [ :index, :show ] do
        collection do
          post :rate
        end
        member do
          post :mark_used
        end
      end
      resources :manual_events, only: [ :create ]

      get "chat", to: "chat#show"
      post "chat/stream", to: "chat#stream"

      resources :activity_logs, only: [ :index ] do
        collection do
          get :active
          post :cleanup_stale
        end
        member do
          get :dev_logs
          post :cancel
          post :retry, action: :retry_job
        end
      end

      get "billing", to: "billing#show"
      post "billing/trial", to: "billing#start_trial"
      post "billing/charges", to: "billing#create_charge"
      get "billing/charges/:invoice_id", to: "billing#charge", as: :billing_charge, constraints: { invoice_id: %r{[^/]+} }
    end
  end

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
