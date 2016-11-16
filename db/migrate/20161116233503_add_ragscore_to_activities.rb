class AddRagscoreToActivities < ActiveRecord::Migration
  def change
    add_column :activities, :rag_score, :integer
  end
end
