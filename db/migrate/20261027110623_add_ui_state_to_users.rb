# Small bits of interface state per user, namespaced by key. "dismissed" maps a notice's name to when the
# user closed it: { "dismissed" => { "first_numbers" => "2026-10-27T11:00:00Z" } }.
class AddUiStateToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :ui_state, :jsonb, null: false, default: {}
    add_check_constraint :users, "jsonb_typeof(ui_state) = 'object'", name: "users_ui_state_object"
  end
end
