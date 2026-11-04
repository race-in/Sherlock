# A user can run several qui instances, one per machine for example. Each address is added once.
class AllowSeveralQuiConnectionsPerUser < ActiveRecord::Migration[8.1]
  def change
    remove_index :qui_connections, :user_id, unique: true
    add_index :qui_connections, [ :user_id, :url ], unique: true
  end
end
