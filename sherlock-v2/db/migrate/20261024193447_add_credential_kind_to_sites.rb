# What a tracker asks for. Sherlock is built for API keys. A passkey is the one in the user's
# torrents, too sensitive to keep for other people, so passkey trackers start switched off and an
# admin running their own Sherlock turns them on.
class AddCredentialKindToSites < ActiveRecord::Migration[8.1]
  def up
    execute "CREATE TYPE site_credential_kind AS ENUM ('api_key', 'passkey')"
    add_column :sites, :credential_kind, :site_credential_kind, null: false, default: "api_key"
  end

  def down
    remove_column :sites, :credential_kind
    execute "DROP TYPE site_credential_kind"
  end
end
