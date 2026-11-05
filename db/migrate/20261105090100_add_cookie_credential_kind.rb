class AddCookieCredentialKind < ActiveRecord::Migration[8.1]
  def up
    execute "ALTER TYPE site_credential_kind ADD VALUE IF NOT EXISTS 'cookies'"
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "PostgreSQL enum values cannot be safely removed."
  end
end
