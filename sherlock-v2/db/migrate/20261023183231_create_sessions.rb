class CreateSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :sessions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      # Null when the request carried none, e.g. curl without a User-Agent.
      t.text :ip_address
      t.text :user_agent

      t.timestamps
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE TRIGGER set_updated_at_on_sessions
          BEFORE UPDATE ON sessions
          FOR EACH ROW EXECUTE FUNCTION set_updated_at();
        SQL
      end
    end
  end
end
