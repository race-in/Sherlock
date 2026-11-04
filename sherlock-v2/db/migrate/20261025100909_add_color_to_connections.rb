# A tracker's chart color, picked by the user in their tracker settings. Empty until they pick one,
# in which case the site's default applies (Site#default_color).
class AddColorToConnections < ActiveRecord::Migration[8.1]
  def up
    add_column :connections, :color, :text
    execute <<~SQL
      ALTER TABLE sherlockdb.connections
        ADD CONSTRAINT connections_color_format CHECK (color IS NULL OR color ~ '^#[0-9a-f]{6}$');
    SQL
  end

  def down
    remove_column :connections, :color
  end
end
