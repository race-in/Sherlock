# self_hosted_reason: why a tracker can only be added on a Sherlock you run yourself (SELF_HOSTED=true).
# Null means it works on any Sherlock. This replaces switching passkey trackers off by default, so they
# start switched on again and the admin switch goes back to meaning only "on" or "off".
#
# tracker_hosts: the announce hosts of the tracker, which differ from its website (Redacted announces
# on flacsfor.me). qui reports torrents by announce URL, so this is how they're matched to a site.
class AddSelfHostedToSites < ActiveRecord::Migration[8.1]
  def up
    add_column :sites, :self_hosted_reason, :text
    add_column :sites, :tracker_hosts, :text, array: true, null: false, default: []
    add_check_constraint :sites, "char_length(self_hosted_reason) <= 300", name: "sites_self_hosted_reason_length"
    execute "UPDATE sites SET is_active = true WHERE credential_kind = 'passkey'"
  end

  def down
    remove_column :sites, :self_hosted_reason
    remove_column :sites, :tracker_hosts
  end
end
