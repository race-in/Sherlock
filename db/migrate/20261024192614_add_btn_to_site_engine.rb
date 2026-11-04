class AddBtnToSiteEngine < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TYPE site_engine ADD VALUE IF NOT EXISTS 'btn'"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Postgres can't drop an enum value"
  end
end
