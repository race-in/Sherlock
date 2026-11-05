# Runs on every release, so everything here is an upsert.

SITES = [
  {
    slug: "redacted", name: "Redacted", short_name: "RED", engine: "gazelle", tier: "supported",
    base_url: "https://redacted.sh", tracker_hosts: [ "flacsfor.me" ], api_key_url: "https://redacted.sh/user.php?action=edit",
    privacy_settings_url: "https://redacted.sh/user.php?action=edit", privacy_hint: "Under Paranoia, tick the stats you want Sherlock to see, and save.",
    key_instructions: "Open your settings, go to Access Settings and create an API key. Sherlock needs no permissions, so you can leave them all unticked."
  },
  {
    slug: "orpheus", name: "Orpheus", short_name: "OPS", engine: "gazelle", tier: "supported",
    base_url: "https://orpheus.network", tracker_hosts: [ "opsfet.ch" ], api_key_url: "https://orpheus.network/user.php?action=edit",
    privacy_settings_url: "https://orpheus.network/user.php?action=edit", privacy_hint: "Under Paranoia, tick the stats you want Sherlock to see, and save.",
    key_instructions: "Open your settings, go to Access Settings and create an API key with as few permissions as it allows."
  },
  { slug: "avistaz", name: "AvistaZ", short_name: "AvZ", tier: "unsupported", unsupported_reason: "Needs your login, not an API key." },
  { slug: "torrentleech", name: "TorrentLeech", short_name: "TL", tier: "unsupported", unsupported_reason: "Needs your login, not an API key." },
  { slug: "iptorrents", name: "IPTorrents", short_name: "IPT", tier: "unsupported", unsupported_reason: "Needs your login, not an API key." },
  {
    slug: "hdbits", name: "HDBits", short_name: "HDB", engine: "hdbits", tier: "supported", credential_kind: "passkey",
    base_url: "https://hdbits.org", tracker_hosts: [ "hdbits.org" ], api_key_url: "https://hdbits.org/",
    credential_warning: "HDBits has no API key, only the passkey from your torrents. Anyone holding it can download as you, so only give it to a Sherlock whose admin you trust.",
    key_instructions: "Your passkey is on your HDBits profile page. Sherlock needs it together with your username. It's the same passkey as in your torrents, so only use it on a Sherlock whose admin you trust."
  },
  {
    slug: "broadcasthenet", name: "BroadcasTheNet", short_name: "BTN", engine: "btn", tier: "supported",
    base_url: "https://api.broadcasthe.net", tracker_hosts: [ "landof.tv" ], api_key_url: "https://broadcasthe.net/user.php?action=edit",
    key_instructions: "Your API key is in your BTN profile settings. BTN only answers from addresses you approved, so after the first test, check your notices on BTN, approve Sherlock's address, and test again."
  },
  {
    slug: "phoenixproject", name: "PhoenixProject", short_name: "PxP", engine: "gazelle", tier: "beta",
    base_url: "https://phoenixproject.app", api_key_url: "https://phoenixproject.app/user.php?action=edit",
    privacy_settings_url: "https://phoenixproject.app/user.php?action=edit", privacy_hint: "Under Paranoia, tick the stats you want Sherlock to see, and save.",
    key_instructions: "Open your settings, go to Access Settings and create an API key with as few permissions as it allows."
  },
  {
    slug: "desigaane", name: "DesiGaane", short_name: "DG", engine: "gazelle", tier: "beta",
    base_url: "https://desigaane.rocks", api_key_url: "https://desigaane.rocks/user.php?action=edit",
    privacy_settings_url: "https://desigaane.rocks/user.php?action=edit", privacy_hint: "Under Paranoia, tick the stats you want Sherlock to see, and save.",
    key_instructions: "Open your settings, go to Access Settings and create an API key with as few permissions as it allows."
  },
  {
    slug: "anthelion", name: "Anthelion", short_name: "ANT", engine: "anthelion", tier: "beta",
    base_url: "https://anthelion.me", api_key_url: "https://anthelion.me/user.php?action=edit",
    key_instructions: "Open your settings and go to Access Settings for your API key. Sherlock also needs your username."
  },
  {
    slug: "animebytes", name: "AnimeBytes", short_name: "AB", engine: "animebytes", tier: "beta",
    base_url: "https://animebytes.tv", api_key_url: "https://animebytes.tv/user.php?action=edit",
    key_instructions: "Your API key is in your account settings. Sherlock also needs your username, since the API doesn't report it."
  },
  { slug: "passthepopcorn", name: "PassThePopcorn", short_name: "PTP", tier: "unsupported", unsupported_reason: "Not supported yet." },
  {
    slug: "gazellegames", name: "GazelleGames", short_name: "GGn", engine: "gazellegames", tier: "supported",
    base_url: "https://gazellegames.net", tracker_hosts: [ "gazellegames.net" ], api_key_url: "https://gazellegames.net/user.php?action=edit",
    privacy_settings_url: "https://gazellegames.net/user.php?action=edit", privacy_hint: "Under Paranoia, tick the stats you want Sherlock to see, and save.",
    key_instructions: "Open your settings and create an API key with only the User permission ticked."
  },
  *{
    "aither" => [ "Aither", "ATH", "https://aither.cc" ],
    "blutopia" => [ "Blutopia", "BLU", "https://blutopia.cc" ],
    "darkpeers" => [ "DarkPeers", "DP", "https://darkpeers.org" ],
    "homiehelpdesk" => [ "HomieHelpDesk", "HHD", "https://homiehelpdesk.net" ],
    "itatorrents" => [ "ItaTorrents", "ITT", "https://itatorrents.xyz" ],
    "lst" => [ "LST", "LST", "https://lst.gg" ],
    "oldtoons" => [ "OldToons", "OTW", "https://oldtoons.world" ],
    "onlyencodes" => [ "OnlyEncodes", "OE", "https://onlyencodes.cc" ],
    "racing4everyone" => [ "Racing4Everyone", "R4E", "https://racing4everyone.eu" ],
    "rastastugan" => [ "Rastastugan", "RAS", "https://rastastugan.org" ],
    "reelflix" => [ "ReelFlix", "RF", "https://reelflix.cc" ],
    "seedpool" => [ "Seedpool", "SP", "https://seedpool.org" ],
    "uploadcx" => [ "ULCX", "ULCX", "https://upload.cx" ],
    "yuscene" => [ "YU-Scene", "YUS", "https://yu-scene.net" ]
  }.map do |slug, (name, short_name, base_url)|
    # UNIT3D keeps the API key page under the user's own profile, so the link can only go to the site.
    { slug:, name:, short_name:, engine: "unit3d", tier: "beta", base_url:, api_key_url: base_url,
      key_instructions: "Open your profile, go to Settings, then API key, and copy the key marked Active." }
  end
].freeze

SITES.each do |attributes|
  site = Site.find_or_initialize_by(slug: attributes[:slug])
  # Who may use a tracker is the admin's choice in /admin, so seeds only set it for a new site. Most
  # trackers don't let members hand their key to another server, so every tracker starts off. The admin
  # turns on the ones they use, in the setup on their dashboard or in /admin.
  site.availability = "off" if site.new_record?
  site.update!({ engine: nil, base_url: nil, api_key_url: nil, key_instructions: nil, unsupported_reason: nil, credential_kind: "api_key",
    credential_warning: nil, tracker_hosts: [], privacy_settings_url: nil, privacy_hint: nil }.merge(attributes))
end

# Integrations start out for granted people only, as the column default says: a qui key can do
# everything its user can. The admin opens them up in /admin.
Integration.find_or_create_by!(slug: "qui") { _1.name = "qui" }

return unless Rails.env.development?

# Demo data. The dev user is what /dev/session signs in as. Keys are fake, which is why
# config/recurring.yml only polls in production.
def seed_user(username, invited_by: nil, **attributes)
  User.find_or_create_by!(username:) do |user|
    user.password = "sherlock-dev-password"
    user.invited_by_user = invited_by
    user.time_zone = "Europe/Berlin"
    user.tracker_rules_accepted_at = Time.current
    user.onboarding_completed_at = Time.current
    user.assign_attributes(attributes)
  end
end

def seed_history(connection, uploaded:, downloaded:, upload_rate:, download_rate:, seed:)
  return if connection.snapshots.exists?

  random = Random.new(seed)
  seeding = 400 + random.rand(200)
  snatched = 900 + random.rand(300)
  uploads = 20 + random.rand(40)
  forum_posts = 100 + random.rand(400)
  torrent_comments = 10 + random.rand(40)
  start = 182.days.ago.beginning_of_hour
  rows = (0..(182 * 24)).map do |hour|
    time = start + hour.hours
    burst = random.rand < 0.04 ? random.rand(20..60) : 1
    # Busier in the evening and at the weekend, so the pattern charts have something to show.
    local = time.in_time_zone("Europe/Berlin")
    rhythm = (1 + Math.sin((local.hour - 14) * Math::PI / 12)) * (local.on_weekend? ? 1.5 : 1)
    uploaded += (upload_rate * random.rand(0.2..1.8) * burst * rhythm).round
    downloaded += (download_rate * random.rand(0.0..2.0)).round if random.rand < 0.3
    seeding += random.rand(-1..2) if random.rand < 0.2
    snatched += 1 if random.rand < 0.15
    uploads += 1 if random.rand < 0.01
    forum_posts += 1 if random.rand < 0.05
    torrent_comments += 1 if random.rand < 0.02
    { connection_id: connection.id, uploaded:, downloaded:, ratio: (uploaded.to_d / downloaded).round(2),
      required_ratio: 0.6, seeding:, leeching: random.rand < 0.1 ? 1 : 0, snatched:, uploads:, forum_posts:,
      torrent_comments:, user_class: "Power User",
      created_at: time, updated_at: time }
  end
  Snapshot.insert_all!(rows)
  connection.update!(polled_at: rows.last[:created_at])
end

dev = seed_user("dev", is_admin: true, invite_limit: 10)
watson = seed_user("watson", invited_by: dev)
seed_user("lestrade", invited_by: watson)
seed_user("hudson", invited_by: dev, is_disabled: true)
seed_user("mycroft", invited_by: dev, onboarding_completed_at: nil, tracker_rules_accepted_at: nil)

unless dev.created_invites.exists?
  dev.created_invites.create!
  dev.created_invites.create!(revoked_at: Time.current)
end

# Where tracker staff reach this Sherlock. Switching a site to your key in /admin needs it.
InstanceSetting.current.update!(tracker_contact: "sherlock-dev@example.com") if InstanceSetting.tracker_contact.blank?

redacted = Site.find_by!(slug: "redacted")
orpheus = Site.find_by!(slug: "orpheus")
# The demo connections below need their trackers on.
[ redacted, orpheus ].each { _1.update!(availability: "everyone") if _1.off? }
gib = 1024**3

dev_red = dev.connections.find_or_create_by!(site: redacted) do |c|
  c.credential = "demo-key-not-real"
  c.external_username = "dev"
  c.external_user_id = "1001"
end
seed_history(dev_red, uploaded: 2_300 * gib, downloaded: 640 * gib, upload_rate: 0.9 * gib, download_rate: 0.4 * gib, seed: 1)

dev_ops = dev.connections.find_or_create_by!(site: orpheus) do |c|
  c.credential = "demo-key-not-real"
  c.external_username = "dev"
  c.external_user_id = "2002"
end
seed_history(dev_ops, uploaded: 610 * gib, downloaded: 380 * gib, upload_rate: 0.25 * gib, download_rate: 0.3 * gib, seed: 2)

watson_red = watson.connections.find_or_create_by!(site: redacted) do |c|
  c.credential = "demo-key-not-real"
  c.external_username = "watson"
  c.external_user_id = "1002"
end
seed_history(watson_red, uploaded: 120 * gib, downloaded: 90 * gib, upload_rate: 0.1 * gib, download_rate: 0.1 * gib, seed: 3)

# Cross-seeds as qui would report them, one a day for 60 days.
[ [ dev_red, 900, 0.30 ], [ dev_ops, 420, 0.62 ] ].each.with_index do |(connection, torrents, share), index|
  next if connection.cross_seed_snapshots.exists?

  random = Random.new(10 + index)
  rows = (0...60).map do |day|
    time = (60 - day).days.ago.beginning_of_day + 12.hours
    seeding = torrents + day * 3 + random.rand(5)
    crossed = (seeding * (share + day * 0.002)).round
    { connection_id: connection.id, torrents: seeding, size: seeding * 900 * 1024**2, uploaded: (1_200 + day * 9) * gib,
      cross_seeded: crossed, cross_seeded_size: crossed * 900 * 1024**2, cross_seeded_uploaded: (300 + day * 4) * gib,
      cross_seeded_paused: random.rand(0..12),
      created_at: time, updated_at: time }
  end
  CrossSeedSnapshot.insert_all!(rows)
end

puts "Seeded. Sign in at /dev/session, or as dev / sherlock-dev-password."
