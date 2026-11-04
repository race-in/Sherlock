# One row per person an admin let use an integration that's only for granted people.
class CreateIntegrationGrants < ActiveRecord::Migration[8.1]
  def change
    create_table :integration_grants do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :integration, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end
    add_index :integration_grants, %i[user_id integration_id], unique: true

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE TRIGGER set_updated_at_on_integration_grants
          BEFORE UPDATE ON integration_grants
          FOR EACH ROW EXECUTE FUNCTION set_updated_at();
        SQL
      end
    end
  end
end
