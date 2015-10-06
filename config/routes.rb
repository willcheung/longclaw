Longclaw::Application.routes.draw do

  resources :timesheets
  devise_for :users, :controllers => { :omniauth_callbacks => "omniauth_callbacks", :sessions => "sessions" }
  # You can have the root of your site routed with "root"

  authenticate :user do
    # Rails 4 users must specify the 'as' option to give it a unique name
    root :to => "home#index", :as => "authenticated_root"

    resources :accounts 
    resources :contacts
    resources :projects
    resources :tasks
    resources :timesheets
    #resources :reports

    get "projects/show"
    get "search/results"
  end

  devise_scope :user do
  	root to: "sessions#new"
	end

end
