Rails.application.routes.draw do
  root "home#show"

  resource :session
  resource :registration, only: %i[new create]
  resource :magic_link, only: %i[new create show]

  # Funnel: onboarding, paywall (fake door), waitlist
  resource :start, only: %i[show create], controller: "onboardings"
  resource :checkout, only: :create
  resources :waitlist_entries, only: %i[new create show], path: "waitlist"
  get "privacy", to: "pages#privacy"
  get "terms", to: "pages#terms"

  # Reader
  resources :episodes, only: :show do
    resource :progress, only: :update, controller: "reading_progresses"
  end
  resources :user_words, only: %i[create destroy], param: :lexeme_id
  resource :review, only: :show do
    post :answer
  end
  resources :passwords, param: :token

  # User stories and sharing (wave 7)
  get "s/:share_token", to: "episodes#show", as: :shared_episode # reader without an account + OG preview
  resources :episodes, only: [] do
    resources :shares, only: :create   # story_shared { channel }
    resources :reports, only: :create  # "Report"
  end
  resources :stories, only: %i[index new create show update destroy] do
    post :reset_link, on: :member
  end
  get "community", to: "community#index", as: :community
  resources :authors, only: :show, path: "u", param: :public_id do
    resource :block, only: %i[create destroy], controller: "author_blocks" # "Hide author"
  end

  namespace :admin do
    root "series#index"

    resources :series do
      resources :characters, shallow: true, except: %i[index show]
      resources :episodes, only: %i[new create]
    end
    resources :episodes, only: %i[show edit update destroy] do
      member do
        post :publish
        post :unpublish
      end
    end
    resources :panels, only: %i[edit update]
    resources :bubbles, only: %i[edit update] do
      resources :tokens, shallow: true, only: %i[new create edit update destroy]
    end
    resources :lexemes, only: %i[index edit update]
    resources :imports, only: %i[new create]

    # User stories: list with cost, the report queue, moderation actions
    resources :stories, only: :index do
      member do
        post :hide
        post :approve
        post :ban_author
      end
    end
    resources :reports, only: :index
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check

  # JSON API for native clients (docs/api.md)
  namespace :api do
    namespace :v1 do
      resources :guests, only: :create
      resources :sessions, only: :create
      resource :session, only: :destroy
      resources :episodes, only: :show do
        resource :progress, only: :update
      end
      get "s/:share_token", to: "episodes#show", as: :shared_episode # user story by its share link (wave 7)
      resources :user_words, only: %i[index create destroy], param: :lexeme_id
    end
  end

  # PWA
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  mount LetterOpenerWeb::Engine, at: "/letter_opener" if Rails.env.development?

  # Ad landings: /en-ru, /ko-en (keep last, it matches any two-letter pair)
  get ":pair", to: "landings#show", as: :landing, constraints: { pair: /[a-z]{2}-[a-z]{2}/ }
end
