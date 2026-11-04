class AddAnthelionAndAnimebytesToSiteEngine < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TYPE site_engine ADD VALUE IF NOT EXISTS 'anthelion'"
    execute "ALTER TYPE site_engine ADD VALUE IF NOT EXISTS 'animebytes'"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Postgres can't drop an enum value"
  end
end
