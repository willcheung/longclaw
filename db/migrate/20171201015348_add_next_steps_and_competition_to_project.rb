class AddNextStepsAndCompetitionToProject < ActiveRecord::Migration
  def change
    add_column :projects, :next_steps, :string
    add_column :projects, :competition, :string
  end
end
