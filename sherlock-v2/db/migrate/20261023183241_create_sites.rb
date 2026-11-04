class CreateSites < ActiveRecord::Migration[8.1]
  def change
    create_enum :site_engine, %w[gazelle]
    create_enum :site_tier, %w[supported beta unsupported]

    create_table :sites do |t|
      t.text :slug, null: false
      t.text :name, null: false
      # Null only for unsupported sites, which are listed so people see why they're missing.
      t.enum :engine, enum_type: :site_engine
      t.text :base_url
      t.text :api_key_url
      t.text :key_instructions
      t.text :unsupported_reason
      t.enum :tier, enum_type: :site_tier, null: false
      t.boolean :is_active, null: false, default: true

      t.timestamps
    end
    add_index :sites, :slug, unique: true
    add_check_constraint :sites, "slug ~ '^[a-z0-9-]+$'", name: "sites_slug_format"
    add_check_constraint :sites, <<~SQL.squish, name: "sites_tier_fields"
      (tier = 'unsupported' AND unsupported_reason IS NOT NULL)
      OR (tier <> 'unsupported' AND engine IS NOT NULL AND base_url ~ '^https://' AND api_key_url IS NOT NULL AND key_instructions IS NOT NULL)
    SQL

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE TRIGGER set_updated_at_on_sites
          BEFORE UPDATE ON sites
          FOR EACH ROW EXECUTE FUNCTION set_updated_at();
        SQL
      end
    end
  end
end
