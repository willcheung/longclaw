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
      member do
        get "render_pinned_tab"
        get "pinned" => 'projects#pinned_tab'
        get "tasks" => 'projects#tasks_tab'
        get "insights" => 'projects#insights_tab'
        get "arg" => 'projects#arg_tab'
        get "filter" => 'projects#filter_timeline'
        get "more" => 'projects#more_timeline'
        get "network_map"
        get "lookup"
        post "refresh"
      end
      resources :project_subscribers, param: :user_id, only: [:destroy, :create]
      post "project_subscribers/create_all"
    end
    post "/project_bulk" => 'projects#bulk'
    delete "project_subscribers/destroy_other"
    resources :project_members
    resources :users
    resources :notifications, only: [:index, :update, :create]
    resources :salesforce, only: [:index]
    get "salesforce/disconnect/:id" => 'salesforce#disconnect'
    post "/link_salesforce" => 'salesforce#link_salesforce_account'
    post "/salesforce_refresh" => 'salesforce#refresh_accounts'
    post "/salesforce_opp_refresh" => 'salesforce#refresh_opportunities'
    post "/salesforce_activities_refresh" => 'salesforce#refresh_activities'
    get "/delete_salesforce_account/:id" => 'salesforce#remove_account_link'

    scope "settings", controller: :settings, as: 'settings' do
      get "/" => "settings#index"
      get "users"
      get "alerts"
      post "alerts" => "settings#create_for_alerts"
      get "salesforce" 
      get "salesforce_opportunities" 
      get "salesforce_activities" 
      get "super_user"
      post "invite_user/:user_id" => 'settings#invite_user'
    end

    get "notifications/:id/update_is_complete" => 'notifications#update_is_complete'
    get "notifications/show_email_body/:id" => 'notifications#show_email_body'
    post "notifications/create_from_suggestion"

    get "/delete_single_activity/:id" => 'activities#destroy'
    
    resources :activities, only: [:create, :update, :destroy] do
      resources :comments, only: [:create, :update, :destroy], shallow: true
    end
    #resources :organizations  # not using yet

    scope "search", controller: :search, as: 'search' do
      get "results"
      get "autocomplete_project_name"
      get "autocomplete_project_subs"
      get "autocomplete_project_member"
      get "autocomplete_salesforce_account_name"
    end
    get "onboarding/tutorial", "onboarding/creating_clusters", "onboarding/confirm_projects", "onboarding/fill_in_info"
    post "users/:id/fill_in_info_update" => 'users#fill_in_info_update', :as => 'onboarding_fill_in_info_update'
    
    scope "reports", controller: :reports, as: 'reports' do
      get 'accounts'
      get 'team'
      get 'accounts_dashboard'
      get 'dashboard_data/:sort' => 'reports#dashboard_data'
      get 'account_data/:id' => 'reports#account_data'
    end

    scope "extension", controller: :extension, as: 'extension' do
      get '/' => 'extension#index'
      get 'test'
      get 'account'
      get 'alerts_tasks'
      get 'contacts'
      get 'metrics'
    end

  end

  devise_scope :user do # Unauthenticated user
  	root to: "sessions#new"
    get "/users/auth/salesforcesandbox/callback" => 'omniauth_callbacks#salesforcesandbox'
  end

  # Cluster callback
  post 'onboarding/:user_id/create_clusters/' => 'onboarding#create_clusters'
  get 'home/access_denied'

  scope "hooks", controller: :hooks, as: 'hooks' do
    post "jira"
    post "zendesk"
  end

end
