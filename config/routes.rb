Longclaw::Application.routes.draw do

  devise_for :users, :controllers => { :omniauth_callbacks => "omniauth_callbacks" }
  # You can have the root of your site routed with "root"

  authenticate :user do
    # Rails 4 users must specify the 'as' option to give it a unique name
    root :to => "home#index", :as => "authenticated_root"
    get "home/daily_summary"

    resources :accounts
    post "/account_bulk" => 'accounts#bulk'
    get "/update_salesforce" => 'accounts#set_salesforce_account'

    resources :contacts, only: [:create, :update, :destroy]
    resources :projects do
      resources :project_subscribers, param: :user_id, only: [:destroy, :create]
      post "project_subscribers/create_all"
    end
    delete "project_subscribers/destroy_other"
    resources :project_members
    resources :users
    resources :notifications, only: [:index, :update, :create]
    resources :salesforce, only: [:index]
    get "salesforce/disconnect" => 'salesforce#disconnect'

    get "projects/:id/render_pinned_tab" => 'projects#render_pinned_tab'
    get "projects/:id/pinned" => 'projects#pinned_tab'
    get "projects/:id/tasks" => 'projects#tasks_tab'
    get "projects/:id/insights" => 'projects#insights_tab'

    get "projects/:id/network_map" => 'projects#network_map'
    get "projects/:id/lookup" => 'projects#lookup'

    post "projects/:id/refresh" => 'projects#refresh'
    post "/project_bulk" => 'projects#bulk'

    get "settings/" => 'settings#index'
    get "settings/super_user" => 'settings#super_user'
    post "settings/invite_user/:user_id" => 'settings#invite_user'

    # get "sasuke/" => 'notifications#sasuke'
    get "notifications/:id/update_is_complete" => 'notifications#update_is_complete'
    get "notifications/show_email_body/:id" => 'notifications#show_email_body'

    
    resources :activities, only: [:create, :update, :destroy] do
      resources :comments, only: [:create, :update, :destroy], shallow: true
    end
    #resources :organizations  # not using yet

    get "search/results"
    get "search/autocomplete_project_name"
    get "search/autocomplete_project_subs"
    get "search/autocomplete_project_member"
    get "onboarding/tutorial", "onboarding/creating_clusters", "onboarding/confirm_projects"
    
    # get 'reports/touches/team' => 'reports#touches_by_team'
    # get 'reports/customer'
    # get 'reports/team'
    # get 'reports/lifecycle'
  end

  devise_scope :user do # Unauthenticated user
  	root to: "sessions#new"
	end

  # Cluster callback
  post 'onboarding/:user_id/create_clusters/' => 'onboarding#create_clusters'
  get 'home/access_denied'

end
