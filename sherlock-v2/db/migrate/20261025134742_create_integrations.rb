# Services besides trackers that Sherlock reads, like qui. Each has the same availability as a site:
# everyone, granted (admins and the people in integration_grants) or off. The enum type is now shared.
class CreateIntegrations < ActiveRecord::Migration[8.1]
  def change
    rename_enum :site_availability, :availability

    create_table :integrations do |t|
      t.text :slug, null: false, index: { unique: true }
      t.text :name, null: false
      t.enum :availability, enum_type: :availability, null: false, default: "granted"

      t.timestamps
    end
    add_check_constraint :integrations, "slug ~ '^[a-z0-9-]+$'", name: "integrations_slug_format"
    add_check_constraint :integrations, "char_length(name) <= 60", name: "integrations_name_length"

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE TRIGGER set_updated_at_on_integrations
          BEFORE UPDATE ON integrations
          FOR EACH ROW EXECUTE FUNCTION set_updated_at();
        SQL
      end
    end
  end
end
