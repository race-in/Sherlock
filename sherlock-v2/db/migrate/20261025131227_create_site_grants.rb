# One row per person an admin let use a tracker that's only for granted people, like HDBits.
class CreateSiteGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :site_grants do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :site, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
    add_index :site_grants, %i[user_id site_id], unique: true

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE TRIGGER set_updated_at_on_site_grants
          BEFORE UPDATE ON site_grants
          FOR EACH ROW EXECUTE FUNCTION set_updated_at();
        SQL
      end
    end
  end
end
