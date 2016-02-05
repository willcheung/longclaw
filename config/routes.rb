Longclaw::Application.routes.draw do

  devise_for :users, :controllers => { :omniauth_callbacks => "omniauth_callbacks" }
  # You can have the root of your site routed with "root"

  authenticate :user do
    # Rails 4 users must specify the 'as' option to give it a unique name
    root :to => "home#index", :as => "authenticated_root"

    resources :accounts 
    resources :contacts
    resources :projects
    get "projects/:id/render_pinned_tab" => 'projects#render_pinned_tab'
    
    resources :activities, only: [:update, :create] do
      resources :comments, only: [:create, :update, :delete]
    end
    #resources :organizations  # not using yet

    get "search/results"
    get "onboarding/intro_overall", "onboarding/intro_accounts_projects",
        "onboarding/intro_activites", "onboarding/intro_pinned", "onboarding/creating_clusters", "onboarding/confirm_projects"
  end

  devise_scope :user do
  	root to: "sessions#new"
	end

  # Cluster callback
  post 'onboarding/:user_id/create_clusters/' => 'onboarding#create_clusters'
  get 'home/access_denied'

end
