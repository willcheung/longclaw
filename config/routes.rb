Longclaw::Application.routes.draw do

  devise_for :users, :controllers => { :omniauth_callbacks => "omniauth_callbacks" }
  # You can have the root of your site routed with "root"

  authenticate :user do
    # Rails 4 users must specify the 'as' option to give it a unique name
    root :to => "home#index", :as => "authenticated_root"
    get "home/daily_summary"

    resources :accounts 
    resources :contacts
    resources :projects do
      resources :project_subscribers, param: :user_id, only: [:destroy, :create]
      post "project_subscribers/create_all"
    end
    resources :project_members
    resources :users
    get "projects/:id/render_pinned_tab" => 'projects#render_pinned_tab'
    get "settings/" => 'settings#index'
    get "settings/super_user" => 'settings#super_user'
    post "settings/invite_user/:user_id" => 'settings#invite_user'
    
    resources :activities, only: [:create, :update, :destroy] do
      resources :comments, only: [:create, :update, :destroy], shallow: true
    end
    #resources :organizations  # not using yet

    get "search/results"
    get "search/autocomplete_project_name"
    get "search/autocomplete_project_subs"
    get "onboarding/tutorial", "onboarding/creating_clusters", "onboarding/confirm_projects"
  end

  devise_scope :user do # Unauthenticated user
  	root to: "sessions#new"
	end

  # Cluster callback
  post 'onboarding/:user_id/create_clusters/' => 'onboarding#create_clusters'
  get 'home/access_denied'

end
