class AddIptorrentsEngine < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TYPE site_engine ADD VALUE IF NOT EXISTS 'iptorrents'"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "PostgreSQL enum values cannot be safely removed."
  end
end
