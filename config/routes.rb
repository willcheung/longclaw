Longclaw::Application.routes.draw do

  devise_for :users, :controllers => { :omniauth_callbacks => "omniauth_callbacks" }
  # You can have the root of your site routed with "root"

  authenticate :user do
    # Rails 4 users must specify the 'as' option to give it a unique name
    #root :to => "home#index", :as => "authenticated_root"
    root :to => "home#thank_you", :as => "authenticated_root"

    resources :accounts 
    resources :contacts
    resources :projects

    get "search/results"
    get "invitations/new"
  end

  devise_scope :user do
  	root to: "sessions#new"
	end

  # Beta Email Teaser
  post 'users/:id/send_beta_teaser_email/' => 'users#send_beta_teaser_email'

end
