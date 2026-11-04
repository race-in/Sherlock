# updated_at is kept by Postgres, not Rails, so raw SQL and psql writes keep it right too. Every new
# table attaches this with a set_updated_at_on_<table> trigger.
class CreateSetUpdatedAtFunction < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE OR REPLACE FUNCTION set_updated_at()
      RETURNS TRIGGER AS $$
      BEGIN
        NEW.updated_at = CURRENT_TIMESTAMP;
        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
    SQL
  end

  def down
    execute "DROP FUNCTION set_updated_at()"
  end
end
