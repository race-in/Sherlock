# Who may use a tracker is now the admin's choice per site instead of SELF_HOSTED: everyone, only
# admins and the people granted it (site_grants), or nobody. Nothing runs in production yet, so the
# old columns go right away.
class ReplaceSelfHostedWithSiteAvailability < ActiveRecord::Migration[8.1]
  def up
    create_enum :site_availability, %w[everyone granted off]
    add_column :sites, :availability, :enum, enum_type: :site_availability, null: false, default: "everyone"
    execute "UPDATE sites SET availability = 'off' WHERE NOT is_active"
    execute "UPDATE sites SET availability = 'granted' WHERE is_active AND self_hosted_reason IS NOT NULL"
    remove_column :sites, :is_active

    remove_check_constraint :sites, name: "sites_self_hosted_reason_length"
    rename_column :sites, :self_hosted_reason, :credential_warning
    add_check_constraint :sites, "char_length(credential_warning) <= 300", name: "sites_credential_warning_length"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
