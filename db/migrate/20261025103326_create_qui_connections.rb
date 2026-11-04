# A user's qui (https://getqui.com), which Sherlock reads cross-seeds from. Self-hosted Sherlocks only.
# One per user.
class CreateQuiConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :qui_connections do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      # Where qui runs, as the user typed it, for example http://192.168.1.10:7476.
      t.text :url, null: false
      # Active Record encryption ciphertext of the qui API key.
      t.text :credential, null: false
      # Saved only after a successful test, so set from the start.
      t.datetime :polled_at, null: false
      # Null while the last poll worked.
      t.text :error_message

      t.timestamps
    end
    add_check_constraint :qui_connections, "url ~ '^https?://' AND char_length(url) <= 300", name: "qui_connections_url_format"
    add_check_constraint :qui_connections, "char_length(error_message) <= 500", name: "qui_connections_error_message_length"

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE TRIGGER set_updated_at_on_qui_connections
          BEFORE UPDATE ON qui_connections
          FOR EACH ROW EXECUTE FUNCTION set_updated_at();
        SQL
      end
    end
  end
end
