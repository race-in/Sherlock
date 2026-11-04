class AddIsTrackerNameShortToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :is_tracker_name_short, :boolean, null: false, default: false
  end
end
