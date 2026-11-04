# A site is read either with each member's own key or with one key from the instance's admin, which
# reads the profiles of members who opted in by putting their Sherlock link on it. Instance-key
# connections have a profile_code instead of a credential.
class AddInstanceKeysToSitesAndConnections < ActiveRecord::Migration[8.1]
  disable_ddl_transaction! # ALTER TYPE ... ADD VALUE

  def up
    execute "ALTER TYPE connection_status ADD VALUE IF NOT EXISTS 'needs_check'"

    transaction do
      create_enum :site_key_owner, %w[member instance]
      add_column :sites, :key_owner, :enum, enum_type: :site_key_owner, null: false, default: "member"
      add_column :sites, :instance_credential, :text
      add_column :sites, :privacy_settings_url, :text
      add_column :sites, :privacy_hint, :text
      add_check_constraint :sites, "key_owner = 'member' OR (instance_credential IS NOT NULL AND privacy_settings_url IS NOT NULL)",
        name: "sites_instance_key_fields"
      add_check_constraint :sites, "privacy_settings_url ~ '^https://'", name: "sites_privacy_settings_url_format"
      add_check_constraint :sites, "char_length(privacy_hint) <= 200", name: "sites_privacy_hint_length"

      change_column_null :connections, :credential, true
      add_column :connections, :profile_code, :text
      add_index :connections, :profile_code, unique: true
      add_check_constraint :connections, "profile_code ~ '^[a-z0-9]{10}$'", name: "connections_profile_code_format"
      add_check_constraint :connections, "credential IS NULL OR profile_code IS NULL", name: "connections_credential_or_profile_code"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
