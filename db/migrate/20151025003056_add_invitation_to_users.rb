class AddInvitationToUsers < ActiveRecord::Migration
  def up
    change_table :users do |t|
      t.datetime   :invitation_created_at
      t.uuid       :invited_by_id
    end
  end

  def down
    change_table :users do |t|
      t.remove :invited_by_id, :invitation_created_at
    end
  end
end
