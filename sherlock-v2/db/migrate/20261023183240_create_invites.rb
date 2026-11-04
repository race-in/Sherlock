class CreateInvites < ActiveRecord::Migration[8.1]
  def change
    create_table :invites do |t|
      t.text :code, null: false
      t.references :created_by_user, null: false, foreign_key: { to_table: :users, on_delete: :cascade }
      # Both null until someone signs up with the code. used_by_user_id goes back to null if that
      # user deletes their account; used_at stays, so the invite still counts as spent.
      t.references :used_by_user, foreign_key: { to_table: :users, on_delete: :nullify }, index: { unique: true }
      t.datetime :used_at
      t.datetime :expires_at, null: false
      # Null unless the creator or an admin revoked it before use.
      t.datetime :revoked_at

      t.timestamps
    end
    add_index :invites, :code, unique: true
    add_check_constraint :invites, "used_by_user_id IS NULL OR used_at IS NOT NULL", name: "invites_used_at_set_when_used"
    add_check_constraint :invites, "NOT (used_at IS NOT NULL AND revoked_at IS NOT NULL)", name: "invites_used_or_revoked"

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE TRIGGER set_updated_at_on_invites
          BEFORE UPDATE ON invites
          FOR EACH ROW EXECUTE FUNCTION set_updated_at();
        SQL
      end
    end
  end
end
