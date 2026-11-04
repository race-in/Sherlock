# Sessions stopped recording IP address and browser, and classic became the only style, in the
# release before this one. Those columns were ignored since; now they go.
class DropSessionDeviceDetailsAndUserStyle < ActiveRecord::Migration[8.1]
  def up
    remove_column :sessions, :ip_address
    remove_column :sessions, :user_agent
    remove_column :users, :style
    execute "DROP TYPE ui_style"
  end

  def down
    execute "CREATE TYPE ui_style AS ENUM ('v2', 'classic')"
    add_column :users, :style, :ui_style, default: "v2", null: false
    add_column :sessions, :user_agent, :text
    add_column :sessions, :ip_address, :text
  end
end
