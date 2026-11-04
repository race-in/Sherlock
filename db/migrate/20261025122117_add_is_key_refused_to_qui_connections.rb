# True once qui refused the key. Sherlock then stops contacting that qui until the user adds its
# address again with a new key, like a tracker that needs a new key.
class AddIsKeyRefusedToQuiConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :qui_connections, :is_key_refused, :boolean, null: false, default: false
  end
end
