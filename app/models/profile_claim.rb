# A member proving a tracker profile is theirs before Sherlock tracks it with the instance key: they
# paste their profile link, put their opt-in link on the profile, and click Check. Lives in the session
# until Connection.connect_profile! saves it, for a signed-in user or with a new account from an open
# invite.
#
# Until Check finds the link, Sherlock knows only the site and the id from the pasted link. It shows and
# keeps nothing it read, and doesn't say whether the account is already on Sherlock.
class ProfileClaim
  class Invalid < StandardError; end

  # How long a Check counts before the member has to check again to finish.
  FRESH_FOR = 30.minutes

  attr_reader :site, :external_user_id, :profile_code, :external_username, :stats, :checked_at

  # The site and member from a profile link, among the sites that read profiles with the instance key.
  # The link's host only picks the site: Sherlock never fetches the pasted URL. The code stays the same
  # when the member pastes the same profile again.
  def self.start(url, sites:, previous: nil)
    uri = URI(url.to_s.strip.then { _1.match?(%r{\A[a-z]+://}i) ? _1 : "https://#{_1}" })
    host = uri.host.to_s.downcase.delete_prefix("www.")
    site = sites.find { _1.host.delete_prefix("www.") == host }
    user_id = site&.adapter&.profile_user_id(uri)
    raise Invalid, "That isn't a profile link from #{sites.map(&:name).to_sentence(last_word_connector: " or ", two_words_connector: " or ")}." unless user_id

    code = previous.profile_code if previous&.site == site && previous.external_user_id == user_id
    new(site:, external_user_id: user_id, profile_code: code || generate_code)
  rescue URI::InvalidURIError
    raise Invalid, "That isn't a link. Copy the address of your profile page."
  end

  def self.generate_code
    SecureRandom.alphanumeric(10, chars: [ *"a".."z", *"0".."9" ])
  end

  def self.from_session(hash)
    return unless hash

    site = Site.find_by(id: hash["site_id"])
    return unless site

    stats = Engines::Stats.new(**hash["stats"].symbolize_keys) if hash["stats"]
    new(site:, external_user_id: hash["external_user_id"], profile_code: hash["profile_code"],
      external_username: hash["external_username"], stats:, checked_at: hash["checked_at"]&.then { Time.zone.parse(_1) })
  end

  def initialize(site:, external_user_id:, profile_code:, external_username: nil, stats: nil, checked_at: nil)
    @site, @external_user_id, @profile_code = site, external_user_id, profile_code
    @external_username, @stats, @checked_at = external_username, stats, checked_at
  end

  # Reads the profile once. Raises Engines::CheckNeeded while the link isn't on it, and Engines::Error
  # when the account is already on Sherlock or the site is full; only then, with the link found, may
  # Sherlock say so.
  def check!
    @stats = @external_username = @checked_at = nil
    raise Engines::Error, "Sherlock is full for #{site.name} right now." if site.full?

    found = Current.set(tracker_purpose: "check") { site.adapter.fetch_profile(external_user_id, profile_code) }
    raise Engines::Error, "This #{site.name} account is already on Sherlock." if site.account_taken?(external_user_id)

    @stats, @external_username, @checked_at = found, found.external_username, Time.current
  end

  def found?
    stats.present?
  end

  # Found, showing what Sherlock needs, and checked recently enough to save.
  def ready?
    found? && stats.trackable? && checked_at > FRESH_FOR.ago
  end

  # What the profile hid when Check read it.
  def hidden_stats
    (Engines::PROFILE_NEEDED + site.profile_stats).select { stats.public_send(_1).nil? }
  end

  def to_session
    { "site_id" => site.id, "external_user_id" => external_user_id, "profile_code" => profile_code,
      "external_username" => external_username, "stats" => stats&.to_h&.as_json, "checked_at" => checked_at&.iso8601 }
  end
end
