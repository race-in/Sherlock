class CreateConnections < ActiveRecord::Migration[8.1]
  def change
    create_enum :connection_status, %w[ok failing needs_key paused]

    create_table :connections do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :site, null: false, foreign_key: { on_delete: :restrict }
      # Both come from the tracker. A connection is only saved after a successful test, so they're set.
      t.text :external_username, null: false
      t.text :external_user_id, null: false
      # Active Record encryption ciphertext of the API key.
      t.text :credential, null: false
      t.enum :status, enum_type: :connection_status, null: false, default: "ok"
      # Null before the first scheduled poll.
      t.datetime :polled_at
      # Null while the last poll worked.
      t.text :error_message
      t.integer :failure_count, null: false, default: 0

      t.timestamps
    end
    add_index :connections, [ :user_id, :site_id ], unique: true
    add_check_constraint :connections, "failure_count >= 0", name: "connections_failure_count_range"
    add_check_constraint :connections, "char_length(error_message) <= 500", name: "connections_error_message_length"

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE TRIGGER set_updated_at_on_connections
          BEFORE UPDATE ON connections
          FOR EACH ROW EXECUTE FUNCTION set_updated_at();
        SQL
      end
    end
  end
end
