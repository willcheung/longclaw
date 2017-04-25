Longclaw::Application.routes.draw do
  unauthenticated do
    get "extension" => "extension#new"
    get "extension/account" => "extension#new"
  end

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
    get "salesforce/disconnect/:id/:return_to_path" => 'salesforce#disconnect', as: "salesforce_disconnect"
    post "/link_salesforce_account" => 'salesforce#link_salesforce_account'
    post "/link_salesforce_opportunity" => 'salesforce#link_salesforce_opportunity'
    post "/salesforce/refresh/:entity_type" => 'salesforce#refresh_salesforce'
    post "/salesforce_activityhistory_update" => 'salesforce#export_activities'
    post "/salesforce_fields_refresh" => 'salesforce#refresh_fields'
    delete "/delete_salesforce_account/:id" => 'salesforce#remove_account_link'
    delete "/delete_salesforce_opportunity/:id" => 'salesforce#remove_opportunity_link'

    resources :basecamp, only: [:index]
    get "basecamp_controller/index"
    post "/sync_stream" => 'basecamps#link_basecamp2_account'
    post "/refresh_stream" => 'basecamps#refresh_stream'
    post "/link_basecamp2_account" => 'basecamps#link_basecamp2_account'
    delete "/delete_basecamp2_account/:id" => 'basecamps#remove_basecamp2_account'
    delete "/basecamp2/disconnect/:id" => 'basecamps#disconnect'

    scope "settings", controller: :settings, as: 'settings' do
      get "/" => "settings#index"
      get "users"
      get "alerts"
      post "alerts" => "settings#create_for_alerts"
      get "custom_fields"
      get "custom_lists"
      get "custom_list/:id" => 'settings#custom_list_show'
      get "salesforce_accounts" 
      get "salesforce_opportunities" 
      get "salesforce_activities" 
      get "basecamp"
      get "basecamp2_projects"
      get "basecamp2_activity"
      get "salesforce_fields" 
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
    
    resources :organizations

    scope "search", controller: :search, as: 'search' do
      get "results"
      get "autocomplete_project_name"
      get "autocomplete_project_subs"
      get "autocomplete_project_member"
      get "autocomplete_salesforce_account_name"
      get "autocomplete_salesforce_opportunity_name"
    end
    get "onboarding/tutorial", "onboarding/creating_clusters", "onboarding/confirm_projects", "onboarding/fill_in_info"
    post "users/:id/fill_in_info_update" => 'users#fill_in_info_update', :as => 'onboarding_fill_in_info_update'
    
    scope "reports", controller: :reports, as: 'reports' do
      get 'd_account_success'
      get 'd_account_sales'
      get 'd_team_success'
      get 'd_team_sales'
      get 'd_executive'
      get 'd_competitors'
      get 'accounts_dashboard'
      get 'ad_sort_data/:sort' => 'reports#ad_sort_data', as: :ad_sort_data
      get 'ad_account_data/:id' => 'reports#ad_account_data', as: :ad_account_data
      get 'team_dashboard'
      get 'td_sort_data/:sort' => 'reports#td_sort_data', as: :td_sort_data
      get 'td_user_data/:id' => 'reports#td_user_data', as: :td_user_data
    end

    scope "extension", controller: :extension, as: 'extension' do
      get '/' => 'extension#index'
      get 'test'
      get 'account'
      get 'alerts_tasks'
      get 'contacts'
      get 'metrics'
      get 'no_account/:domain', to: 'extension#no_account', as: :no_account
      get 'project_error'
      post 'create_account'
    end

    resources :custom_fields, only: [:update]
    resources :custom_fields_metadatum, only: [:create, :update, :destroy]  #for /settings/custom_fields
    resources :custom_lists, only: [:create, :update, :destroy]
    resources :custom_lists_metadata, only: [:create, :update, :destroy]  #for /settings/custom_lists
    resources :custom_configurations, only: [:update, :destroy]
  end

  devise_scope :user do # Unauthenticated user
  	# root to: "sessions#new"
    root to: redirect('/auth/basecamp')
    get '/auth/:provider/callback' => 'setting#basecamp'
    get "/user/omniauth/auth/:provider/:return_to_path", to:  "omniauth_callbacks#user_omniauth_auth_helper", as: :user_omniauth_auth_helper
    # get "/users/auth/salesforcesandbox/callback" => 'omniauth_callbacks#salesforcesandbox'
  end

  get '/users/auth/basecamp2' => 'basecamps#basecamp2'
  get '/users/auth/37signals/callback' => 'settings#basecamp'


  # Cluster callback
  post 'onboarding/:user_id/create_clusters/' => 'onboarding#create_clusters'
  get 'home/access_denied'

  scope "hooks", controller: :hooks, as: 'hooks' do
    post "jira"
    post "zendesk"
  end

end
