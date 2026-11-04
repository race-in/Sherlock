class Site < ApplicationRecord
  enum :engine, { gazelle: "gazelle", hdbits: "hdbits", btn: "btn", gazellegames: "gazellegames", unit3d: "unit3d",
                  anthelion: "anthelion", animebytes: "animebytes" }
  enum :credential_kind, { api_key: "api_key", passkey: "passkey" }, suffix: :credential
  enum :tier, { supported: "supported", beta: "beta", unsupported: "unsupported" }
  # Who may add and poll the tracker: everyone, only admins and the people granted it in /admin, or
  # nobody. Trackers with a credential_warning start as granted.
  enum :availability, { everyone: "everyone", granted: "granted", off: "off" }
  # Whose key reads the tracker: each member's own, or the admin's for everyone, which reads the
  # profiles of members who opted in (see Engines::Gazelle#fetch_profile).
  enum :key_owner, { member: "member", instance: "instance" }, suffix: :key
  enum :pause_reason, { rate_limited: "rate_limited", key_refused: "key_refused", errors: "errors", admin: "admin" }, prefix: :paused_for

  has_many :connections
  has_many :site_grants

  # Who a tracker is set up for, the one choice in its setup (Admin::Sites::SetupsController): nobody,
  # only the admin and the people they grant it to, everyone with their own key, or everyone who opts in
  # on their profile, read with the admin's key.
  AUDIENCES = { off: "Not set up", only_me: "Only you", own_keys: "You and people you invite, with their own key", opt_in: "You and people you invite, who opt in" }.freeze

  encrypts :instance_credential

  # Tracker errors (5xx, timeouts) in a row, across all members, before the site pauses for an hour. Each
  # further one doubles the pause, up to a day.
  FAILURES_BEFORE_PAUSE = 5
  PAUSE_MESSAGES = {
    "rate_limited" => "%{name} asked Sherlock to slow down",
    "key_refused" => "%{name} refused the admin's key",
    "errors" => "%{name} kept failing",
    "admin" => "the admin paused it"
  }.freeze

  # The trackers a user may add, and whose connections keep polling. Connection.pollable says the
  # same in SQL for all users at once.
  scope :available_to, ->(user) {
    sites = where.not(availability: :off).where.not(tier: :unsupported).order(:name)
    user.is_admin? ? sites : sites.everyone.or(sites.where(id: user.site_grants.select(:site_id)))
  }

  # Trackers anyone may join through with an open invite: read with the instance key and open to everyone.
  scope :joinable, -> { instance_key.everyone.where.not(tier: :unsupported).order(:name) }

  def to_param
    slug
  end

  # What the UI calls the tracker: its name, or its short code (BTN, HDB) for people who chose short
  # names in their preferences. Messages saved for later, exports and imports use the name.
  def display_name
    Current.user&.is_tracker_name_short? ? short_name : name
  end

  def audience
    return :off if off?
    return :opt_in if instance_key?

    everyone? ? :own_keys : :only_me
  end

  # Whether members can opt in here: Sherlock reads their profiles with the admin's key.
  def opt_in_possible?
    instance_key_possible? && privacy_settings_url.present?
  end

  def available_to?(user)
    Site.available_to(user).exists?(id)
  end

  # Whether this tracker's engine can read another member's profile with the admin's key.
  def instance_key_possible?
    adapter.respond_to?(:fetch_profile)
  end

  # The stats a profile on this tracker can show, beyond the ones it must (Engines::PROFILE_NEEDED).
  def profile_stats
    adapter.class::PROFILE_STATS
  end

  # Hands out this site's next request slot and returns how many seconds to wait for it. One UPDATE does
  # it for every process at once, and nothing is locked while the caller waits. Raises Engines::Paused
  # while the site is paused, and Engines::Busy if the slot is further away than `within` seconds.
  def reserve_request!(within:, for_key_test: false)
    # uncached: select_value would otherwise answer a repeat of the same UPDATE from the query cache,
    # which jobs and requests turn on, without running it.
    wait = self.class.uncached { self.class.connection.select_value(self.class.sanitize_sql([ <<~SQL, id:, within:, for_key_test: ])) }
      UPDATE sites s
      SET next_request_at = GREATEST(s.next_request_at, clock_timestamp()) + s.request_interval
      WHERE s.id = :id
        AND (s.pause_reason IS NULL OR s.paused_until <= clock_timestamp() OR (:for_key_test AND s.pause_reason = 'key_refused'))
        AND s.next_request_at <= clock_timestamp() + make_interval(secs => :within)
      RETURNING EXTRACT(EPOCH FROM s.next_request_at - s.request_interval - clock_timestamp())
    SQL
    return [ wait.to_f, 0 ].max if wait

    reload
    raise Engines::Paused, "Sherlock paused #{name}: #{pause_message}." if paused? && !(for_key_test && paused_for_key_refused?)

    raise Engines::Busy, "#{name} is busy right now. Try again in a minute."
  end

  # Called with every answer from the tracker. A 429 pauses the site, a 5xx counts towards pausing it,
  # anything else shows the tracker is up.
  def tracker_answered(response)
    case response.code.to_i
    when 429 then rate_limited!(Integer(response["Retry-After"].to_s, exception: false))
    when 500.. then tracker_failed
    else tracker_up
    end
  end

  def rate_limited!(retry_after)
    pause!(:rate_limited, retry_after.to_i.clamp(5.minutes.to_i, 24.hours.to_i).seconds)
  end

  # A 5xx or a timeout.
  def tracker_failed
    streak = self.class.uncached { self.class.connection.select_value("UPDATE sites SET failure_streak = failure_streak + 1 WHERE id = #{id.to_i} RETURNING failure_streak") }
    pause!(:errors, [ 2**(streak - FAILURES_BEFORE_PAUSE), 24 ].min.hours) if streak >= FAILURES_BEFORE_PAUSE
  end

  # Ends a streak of errors, and a timed pause that's over. A pause that's still running stays: the
  # answer may have been on its way when the site paused.
  def tracker_up
    self.class.where(id:).where("failure_streak > 0 OR paused_until <= clock_timestamp()")
      .update_all(failure_streak: 0, pause_reason: nil, paused_until: nil)
  end

  # Without a duration, the pause lasts until someone acts: the admin resumes, or saves a key that works.
  # A timed pause doesn't cut one of those short.
  def pause!(reason, duration = nil)
    sites = self.class.where(id:)
    sites = sites.where(pause_reason: nil).or(sites.where(pause_reason: %w[rate_limited errors])) if duration
    sites.update_all(pause_reason: reason.to_s, paused_until: duration&.from_now)
    reload
  end

  def resume!
    update!(pause_reason: nil, paused_until: nil, failure_streak: 0)
  end

  def paused?(now = Time.current)
    pause_reason.present? && (paused_until.nil? || paused_until > now)
  end

  def pause_message
    format(PAUSE_MESSAGES.fetch(pause_reason), name:)
  end

  # How many members this site can take: half of an hour's request slots, so Checks, tests and a slow
  # hour still fit.
  def capacity
    1.hour.to_i / request_interval.to_i / 2 / requests_per_poll
  end

  def full?
    connections.count >= capacity
  end

  # Whether a tracker account is on this Sherlock already. external_user_id is encrypted without
  # deterministic mode, so this reads the site's connections; a few hundred at most (see capacity).
  def account_taken?(external_user_id)
    Connection.where(site: self).find_each.any? { _1.external_user_id == external_user_id.to_s }
  end

  # Starts reading members' profiles with the admin's key, once the tracker accepted it for the admin's
  # own profile. Members who connected with their own key keep their history: their keys are deleted
  # and they're asked to add their opt-in link instead. The key's own account reads with the key and
  # needs no link (Connection#is_key_owner); a different key hands that over to its account. Saving a
  # working key also ends a key_refused pause.
  def use_instance_key!(api_key)
    raise Engines::Error, "#{name} can't read members' profiles." unless opt_in_possible?
    raise Engines::Error, "Add a contact for tracker staff in Admin → Settings first, so #{name}'s staff can reach you." if InstanceSetting.tracker_contact.blank?

    key = api_key.to_s.strip.presence || instance_credential
    raise Engines::Error, "Enter your #{name} API key." if key.blank?

    owner_id = Current.set(tracker_purpose: "instance_key") { adapter.check_instance_key(key) }
    transaction do
      if member_key? || instance_credential != key
        self.class.connection.exec_update(self.class.sanitize_sql([ <<~SQL, id:, member_key: member_key?, message: "#{name} now reads your profile instead of your key. Add your Sherlock link to it to keep tracking." ]))
          UPDATE connections
          SET credential = NULL, is_key_owner = false, profile_code = substr(md5(random()::text || id::text), 1, 10),
              status = 'needs_check', error_message = :message, failure_count = 0
          WHERE site_id = :id AND (:member_key OR is_key_owner)
        SQL
      end
      update!(key_owner: :instance, instance_credential: key, **(paused_for_key_refused? ? { pause_reason: nil, paused_until: nil } : {}))
      connections.find_each.find { _1.external_user_id == owner_id }&.read_with_instance_key!
    end
  end

  # Back to each member's own key. The admin's key is deleted, and members are asked for theirs.
  def use_member_keys!
    transaction do
      connections.update_all(profile_code: nil, is_key_owner: false, status: "needs_key",
        error_message: "#{name} now needs your own API key. Add it to keep tracking.")
      update!(key_owner: :member, instance_credential: nil, **(paused_for_key_refused? ? { pause_reason: nil, paused_until: nil } : {}))
    end
  end

  # Turning a site off deletes the keys members gave for it: Sherlock only keeps keys for trackers it
  # may use. History stays, and turning the site on again asks for a new key.
  def update_availability!(availability)
    transaction do
      update!(availability:)
      if off?
        connections.where.not(credential: nil).update_all(credential: nil, status: "needs_key",
          error_message: "#{name} is off on this Sherlock, so your key was deleted. Your history is kept. To keep tracking, run your own Sherlock and import your history there.")
      end
    end
  end

  # Whether a torrent announcing to this host belongs to this tracker. Subdomains count, so
  # "gazellegames.net" also covers "tracker.gazellegames.net". Without tracker_hosts, the tracker
  # announces on its website's host, as UNIT3D trackers do.
  def tracker_host?(host)
    (tracker_hosts.presence || [ base_url && self.host ].compact).any? { host == _1 || host.end_with?(".#{_1}") }
  end

  def adapter
    Engines.for(self)
  end

  # Sites whose API needs the username next to the key (HDBits, Anthelion), or doesn't report it
  # (AnimeBytes).
  def needs_username?
    hdbits? || anthelion? || animebytes?
  end

  # What a connection stores from the key form: the bare key, or with a username, both as JSON.
  def credential_from(params)
    key = params[:api_key].to_s.strip
    return key unless needs_username?

    { :username => params[:username].to_s.strip, (hdbits? ? :passkey : :api_key) => key }.to_json
  end

  def host
    URI(base_url).host
  end

  # A member-key Gazelle poll asks three things (index, community_stats, user); everything else one.
  def requests_per_poll
    member_key? && gazelle? ? 3 : 1
  end

  # Short code shown in place of a favicon. Loading the tracker's own icon would make every
  # visitor's browser contact the tracker.
  def monogram
    name.scan(/[A-Z0-9]/).first(2).join.presence || name.first(2).upcase
  end

  # The chart color a tracker starts with, taken from its icon and softened, but never red or green,
  # which mean down and up elsewhere in Sherlock. Black-and-white icons get a grey of their own. A
  # tracker without an entry keeps whatever its slug hashes to in the fallback palette.
  def default_color
    DEFAULT_COLORS.fetch(slug) { FALLBACK_COLORS[slug.sum % FALLBACK_COLORS.size] }
  end

  DEFAULT_COLORS = {
    "redacted" => "#8e90c8", # the headphones
    "orpheus" => "#a2a8b0", # silver
    "hdbits" => "#6f8799",
    "broadcasthenet" => "#2a9bc9",
    "gazellegames" => "#49718e",
    "phoenixproject" => "#f0844f",
    "anthelion" => "#5faed9",
    "animebytes" => "#e0699b",
    "aither" => "#8b8d93",
    "blutopia" => "#2f86d6",
    "darkpeers" => "#5e6168",
    "homiehelpdesk" => "#2ba3a8",
    "itatorrents" => "#8a8f8b",
    "lst" => "#a5a5a5",
    "oldtoons" => "#e39aa3",
    "onlyencodes" => "#f2a23a",
    "racing4everyone" => "#b86b75",
    "rastastugan" => "#7c7f88",
    "reelflix" => "#a35865",
    "seedpool" => "#7fbde3",
    "uploadcx" => "#737680",
    "yuscene" => "#3cc4cc"
  }.freeze

  FALLBACK_COLORS = [ "#5b8fc9", "#3f9c9a", "#d08c4a", "#8f7fc4", "#b8a046", "#7890a8" ].freeze
end
