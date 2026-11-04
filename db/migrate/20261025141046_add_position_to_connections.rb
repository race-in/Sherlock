# Where the tracker sits in the user's own order, which they set by dragging in Settings → Trackers.
# Existing trackers keep the alphabetical order they had.
class AddPositionToConnections < ActiveRecord::Migration[8.1]
  def up
    add_column :connections, :position, :integer, null: false, default: 0
    add_check_constraint :connections, "position >= 0", name: "connections_position_range"
    execute <<~SQL
      UPDATE connections SET position = ordered.position
      FROM (
        SELECT connections.id, ROW_NUMBER() OVER (PARTITION BY connections.user_id ORDER BY sites.name) - 1 AS position
        FROM connections JOIN sites ON sites.id = connections.site_id
      ) ordered
      WHERE connections.id = ordered.id
    SQL
  end

  def down
    remove_column :connections, :position
  end
end
