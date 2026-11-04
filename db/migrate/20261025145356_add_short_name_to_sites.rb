class AddShortNameToSites < ActiveRecord::Migration[8.1]
  # The seeds set these on every release; this only fills the rows already there.
  SHORT_NAMES = {
    "redacted" => "RED", "orpheus" => "OPS", "avistaz" => "AvZ", "torrentleech" => "TL", "iptorrents" => "IPT",
    "hdbits" => "HDB", "broadcasthenet" => "BTN", "phoenixproject" => "PxP", "anthelion" => "ANT", "animebytes" => "AB",
    "passthepopcorn" => "PTP", "gazellegames" => "GGn", "aither" => "ATH", "blutopia" => "BLU", "darkpeers" => "DP",
    "homiehelpdesk" => "HHD", "itatorrents" => "ITT", "lst" => "LST", "oldtoons" => "OTW", "onlyencodes" => "OE",
    "racing4everyone" => "R4E", "rastastugan" => "RAS", "reelflix" => "RF", "seedpool" => "SP", "uploadcx" => "ULCX",
    "yuscene" => "YUS"
  }.freeze

  def up
    add_column :sites, :short_name, :text
    SHORT_NAMES.each { |slug, short_name| execute "UPDATE sites SET short_name = #{connection.quote(short_name)} WHERE slug = #{connection.quote(slug)}" }
    execute "UPDATE sites SET short_name = upper(left(name, 3)) WHERE short_name IS NULL"
    change_column_null :sites, :short_name, false
    add_check_constraint :sites, "char_length(short_name) BETWEEN 1 AND 8", name: "sites_short_name_length"
  end

  def down
    remove_column :sites, :short_name
  end
end
