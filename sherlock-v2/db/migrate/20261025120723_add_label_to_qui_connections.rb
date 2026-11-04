# A name the user gives a qui, like "Seedbox". Null until they pick one; the settings page then shows
# the address.
class AddLabelToQuiConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :qui_connections, :label, :text
    add_check_constraint :qui_connections, "char_length(label) BETWEEN 1 AND 60", name: "qui_connections_label_length"
  end
end
