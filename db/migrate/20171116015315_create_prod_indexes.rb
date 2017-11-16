class CreateProdIndexes < ActiveRecord::Migration
  def change
    reversible do |dir|
      dir.up do
        add_index :accounts, [:owner_id], unique: false, name: 'index_accounts_on_owner_id' if !index_exists?(:accounts, [:owner_id])
        add_index :accounts, [:organization_id], unique: false, name: 'index_accounts_on_organization_id' if !index_exists?(:accounts, [:organization_id])

        add_index :projects, [:owner_id], unique: false, name: 'index_projects_on_owner_id' if !index_exists?(:projects, [:owner_id])
        add_index :projects, [:status], unique: false, name: 'index_projects_on_status' if !index_exists?(:projects, [:status])
        add_index :projects, [:is_confirmed], unique: false, name: 'index_projects_on_is_confirmed' if !index_exists?(:projects, [:is_confirmed])
        add_index :projects, [:is_public], unique: false, name: 'index_projects_on_is_public' if !index_exists?(:projects, [:is_public])

        remove_index :activities, :column => [:project_id], :options => {unique: false, name: 'index_activities_on_project_id'} if index_exists?(:activities, [:project_id])
        add_index :activities, [:project_id, :category, :backend_id], unique: true, name: 'index_activities_on_project_id_and_category_and_backend_id' if !index_exists?(:activities, [:project_id, :category, :backend_id])
        add_index :activities, [:last_sent_date], unique: false, name: 'index_activities_on_last_sent_date' if !index_exists?(:activities, [:last_sent_date])
        add_index :activities, [:category, :project_id, :backend_id], unique: true, name: 'index_activities_on_category_and_project_id_and_backend_id' if !index_exists?(:activities, [:category, :project_id, :backend_id])

        add_index :salesforce_accounts, [:contextsmith_organization_id], unique: false, name: 'index_salesforce_accounts_on_contextsmith_organization_id' if !index_exists?(:salesforce_accounts, [:contextsmith_organization_id])

        add_index :salesforce_opportunities, [:salesforce_account_id], unique: false, name: 'index_salesforce_opportunities_on_salesforce_account_id' if !index_exists?(:salesforce_opportunities, [:salesforce_account_id])
        add_index :salesforce_opportunities, [:contextsmith_project_id], unique: false, name: 'index_salesforce_opportunities_on_contextsmith_project_id' if !index_exists?(:salesforce_opportunities, [:contextsmith_project_id])

        add_index :tracking_requests, [:user_id], unique: false, name: 'index_tracking_requests_on_user_id' if !index_exists?(:tracking_requests, [:user_id])

        add_index :tracking_events, [:date], unique: false, order: {date: :desc}, name: 'index_tracking_events_on_date' if !index_exists?(:tracking_events, [:date])
      end
      dir.down do
        remove_index :accounts, :column => [:owner_id], :options => {unique: false, name: 'index_accounts_on_owner_id'} if index_exists?(:accounts, [:owner_id])
        remove_index :accounts, :column => [:organization_id], :options => {unique: false, name: 'index_accounts_on_organization_id'} if index_exists?(:accounts, [:organization_id])

        remove_index :projects, :column => [:owner_id], :options => {unique: false, name: 'index_projects_on_owner_id'} if index_exists?(:projects, [:owner_id])
        remove_index :projects, :column => [:status], :options => {unique: false, name: 'index_projects_on_status'} if index_exists?(:projects, [:status])
        remove_index :projects, :column => [:is_confirmed], :options => {unique: false, name: 'index_projects_on_is_confirmed'} if index_exists?(:projects, [:is_confirmed])
        remove_index :projects, :column => [:is_public], :options => {unique: false, name: 'index_projects_on_is_public'} if index_exists?(:projects, [:is_public])

        add_index :activities, [:project_id], unique: false, name: 'index_activities_on_project_id' if !index_exists?(:activities, [:project_id])
        remove_index :activities, :column => [:project_id, :category, :backend_id], :options => {unique: true, name: 'index_activities_on_project_id_and_category_and_backend_id'} if index_exists?(:activities, [:project_id, :category, :backend_id])
        remove_index :activities, :column => [:last_sent_date], :options => {name: 'index_activities_on_last_sent_date'} if index_exists?(:activities, [:last_sent_date])
        remove_index :activities, :column => [:category, :project_id, :backend_id], :options => {unique: true, name: 'index_activities_on_category_and_project_id_and_backend_id'} if index_exists?(:activities, [:category, :project_id, :backend_id])

        remove_index :salesforce_accounts, :column => [:contextsmith_organization_id], :options => {name: 'index_salesforce_accounts_on_contextsmith_organization_id'} if index_exists?(:salesforce_accounts, [:contextsmith_organization_id])

        remove_index :salesforce_opportunities, :column => [:salesforce_account_id], :options => {name: 'index_salesforce_opportunities_on_salesforce_account_id'} if index_exists?(:salesforce_opportunities, [:salesforce_account_id])
        remove_index :salesforce_opportunities, :column => [:contextsmith_project_id], :options => {name: 'index_salesforce_opportunities_on_contextsmith_project_id'} if index_exists?(:salesforce_opportunities, [:contextsmith_project_id])

        remove_index :tracking_requests, :column => [:user_id], :options => {unique: false, name: 'index_tracking_requests_on_user_id'} if index_exists?(:tracking_requests, [:user_id])

        remove_index :tracking_events, :column => [:date], :options => {unique: false, order: {date: :desc}, name: 'index_tracking_events_on_date'} if index_exists?(:tracking_events, [:date])
      end
    end
  end
end
