# Redacted and Orpheus. Redacted takes the bare key in the Authorization header; Orpheus wants
# "token <key>" (bare still works there but is deprecated, per OPSnet/Gazelle docs/07-API.md). Both answer
# ajax.php with {"status": "success", "response": {...}} or {"status": "failure", "error": "..."}.
# A poll is three requests: index (user id, bytes, ratio, class), community_stats (seeding, leeching,
# snatched) and user (uploads, forum posts, torrent comments). index needs no key scope. On Redacted,
# community_stats needs none either, but user needs the User scope, which also opens private messages,
# so we don't ask for it: without it those three counts stay nil. Orpheus answers community_stats with
# a bare "failure" but returns seeding, leeching and snatched from user, so those fall back to it.
# The user action hides counts behind paranoia, but never from the account owner, which is who the key
# belongs to.
#
# With the instance key (Site#instance_key?), the user action reads another member's profile instead:
# one request, showing what other members see, so only what the member's paranoia allows, and never
# bonus points, which only index has. Sherlock only reads members who put their opt-in link on it.
class Engines::Gazelle
  ACCESS_DENIED_ERRORS = [ "invalid token" ].freeze
  AUTH_PREFIXES = { "orpheus" => "token " }.freeze
  MESSAGE_LIMIT = 200
  # What a profile may show besides uploaded and downloaded, depending on the member's paranoia.
  PROFILE_STATS = %i[ratio seeding leeching snatched uploads torrent_comments].freeze

  # The tracker answered, but with "failure" and a reason other than a bad key.
  class Failure < Engines::Error; end

  def initialize(site)
    @site = site
  end

  def fetch(api_key)
    index = ajax(api_key, "index")
    community = optional(api_key, "community_stats", userid: index.fetch("id"))
    profile = optional(api_key, "user", id: index.fetch("id"))["community"] || {}
    userstats = index.fetch("userstats")

    Engines::Stats.new(
      external_user_id: index.fetch("id").to_s,
      external_username: index.fetch("username"),
      uploaded: Integer(userstats.fetch("uploaded")),
      downloaded: Integer(userstats.fetch("downloaded")),
      ratio: decimal(userstats["ratio"]),
      required_ratio: decimal(userstats["requiredratio"]),
      bonus_points: decimal(userstats["bonusPoints"]),
      seeding: count(community.fetch("seeding") { profile["seeding"] }),
      leeching: count(community.fetch("leeching") { profile["leeching"] }),
      snatched: count(community.fetch("snatched") { profile["snatched"] }),
      hit_and_runs: nil,
      user_class: userstats["class"].presence,
      uploads: count(profile["uploaded"]),
      forum_posts: count(profile["posts"]),
      torrent_comments: count(profile["torrentComments"])
    )
  rescue KeyError, TypeError, ArgumentError
    raise Engines::Error, "#{@site.name} sent a response Sherlock doesn't understand."
  end

  # The member's id from a profile link like https://redacted.sh/user.php?id=123, or nil.
  def profile_user_id(uri)
    id = URI.decode_www_form(uri.query.to_s).to_h["id"].to_s
    id if uri.path == "/user.php" && id.match?(/\A[1-9]\d{0,9}\z/)
  end

  # Reads a member's profile with the instance key. Raises Engines::CheckNeeded when the member's opt-in
  # link isn't on it, before looking at anything else, or when the account is disabled or the tracker
  # won't show the profile. Stats the profile hides come back nil. If the tracker refuses the instance
  # key itself, the whole site pauses until the admin saves one that works.
  def fetch_profile(user_id, profile_code)
    profile = ajax(@site.instance_credential, "user", id: user_id)
    text = profile.values_at("profileText", "bbProfileText").join("\n")
    raise Engines::CheckNeeded, "The Sherlock link isn't on your #{@site.name} profile." unless Engines.opt_in_link?(text, profile_code)
    raise Engines::CheckNeeded, "#{@site.name} reports this account as disabled." if profile.dig("personal", "enabled") == false

    stats, community = profile["stats"] || {}, profile["community"] || {}
    Engines::Stats.new(
      external_user_id: user_id.to_s,
      external_username: profile.fetch("username"),
      uploaded: lenient_count(stats["uploaded"]),
      downloaded: lenient_count(stats["downloaded"]),
      ratio: decimal(stats["ratio"]),
      required_ratio: decimal(stats["requiredRatio"]),
      bonus_points: nil,
      seeding: lenient_count(community["seeding"]),
      leeching: lenient_count(community["leeching"]),
      snatched: lenient_count(community["snatched"]),
      hit_and_runs: nil,
      user_class: profile.dig("personal", "class").presence,
      uploads: lenient_count(community["uploaded"]),
      forum_posts: lenient_count(community["posts"]),
      torrent_comments: lenient_count(community["torrentComments"])
    )
  rescue Engines::AccessDenied
    @site.pause!(:key_refused)
    raise Engines::Paused, "Sherlock can't read #{@site.name} profiles right now. Try again later."
  rescue Failure
    raise Engines::CheckNeeded, "#{@site.name} didn't show this profile. The account may be disabled, or the link may be wrong."
  rescue KeyError, TypeError, NoMethodError
    raise Engines::Error, "#{@site.name} sent a response Sherlock doesn't understand."
  end

  # Before the admin's key reads everyone: it must work, and reach the user action for its own profile,
  # which needs the User scope on Redacted. Returns the key's own user id.
  def check_instance_key(api_key)
    id = ajax(api_key, "index").fetch("id")
    ajax(api_key, "user", id:)
    id.to_s
  rescue Failure => error
    raise Engines::Error, "#{error.message} The key needs the User permission, so Sherlock can read profiles."
  end

  private
    # The key is already known to work by now, so any refusal here means it lacks the scope.
    def optional(api_key, action, **params)
      ajax(api_key, action, **params)
    rescue Engines::Withheld
      raise
    rescue Engines::Error
      {}
    end

    def ajax(api_key, action, **params)
      uri = URI.join(@site.base_url, "/ajax.php")
      uri.query = URI.encode_www_form(action:, **params)
      response = Engines::Http.get(uri, "Authorization" => "#{AUTH_PREFIXES[@site.slug]}#{api_key}", site: @site)

      case response.code.to_i
      when 200
        body = parse(response.body)
        return body.fetch("response") if body["status"] == "success"

        error = message(body["error"].presence || "no reason given", api_key)
        raise ACCESS_DENIED_ERRORS.include?(error.downcase) ? Engines::AccessDenied : Failure,
          "#{@site.name} said: #{error}"
      when 401, 403
        raise Engines::AccessDenied, "#{@site.name} returned #{response.code}. Your API key may be wrong or revoked."
      when 429
        raise Engines::RateLimited, "#{@site.name} asked us to slow down."
      else
        raise Engines::Error, "#{@site.name} returned HTTP #{response.code}."
      end
    end

    def parse(body)
      JSON.parse(body)
    rescue JSON::ParserError
      raise Engines::Error, "#{@site.name} sent a response that isn't JSON."
    end

    # Tracker error texts are shown and saved. Cap them, since an error can be a whole HTML page, and
    # make sure the key can't come back in one.
    def message(text, api_key)
      text.to_s.scrub("").gsub(api_key, "[key]").squish.truncate(MESSAGE_LIMIT)
    end

    def decimal(value)
      return if value.nil?

      BigDecimal(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    # A profile field paranoia may hide: nil when it's missing, null or not a number.
    def lenient_count(value)
      Integer(value.to_s.delete(","), exception: false) unless value.nil?
    end

    # community_stats sends counts as text with thousands separators, like "1,413".
    def count(value)
      Integer(value.to_s.delete(",")) unless value.nil?
    end
end
