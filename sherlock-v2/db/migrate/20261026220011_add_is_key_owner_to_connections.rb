# The admin's own account on a tracker read with the instance key. It reads with that key, like the
# admin's own key would, so it needs no opt-in link and stores no key of its own.
class AddIsKeyOwnerToConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :connections, :is_key_owner, :boolean, null: false, default: false
    add_check_constraint :connections, "NOT is_key_owner OR (credential IS NULL AND profile_code IS NULL)",
      name: "connections_key_owner_reads_with_instance_key"
  end
end
