# GazelleGames. Gazelle underneath, but its API is api.php?request=..., with the key in an X-API-Key
# header, and answers {"status": "success", "response": {...}} or {"status": "failure", "error": "..."}.
# A poll is one quick_user request, which needs the key's User permission. quick_user also returns the
# account's passkey and authkey; Sherlock reads neither. Stats there are cached by GGn, so they can lag.
#
# With the instance key (Site#instance_key?), request=user&id= reads another member's profile instead:
# what other members see, so only what the member's paranoia allows. Sherlock only reads members who put
# their opt-in link on it.
class Engines::Gazellegames
  MESSAGE_LIMIT = 200
  # What a profile may show besides uploaded and downloaded, depending on the member's paranoia.
  PROFILE_STATS = %i[ratio seeding leeching snatched uploads torrent_comments].freeze

  # The tracker answered, but with "failure" and a reason other than a bad key.
  class Failure < Engines::Error; end

  def initialize(site)
    @site = site
  end

  def fetch(api_key)
    user = request(api_key, "quick_user")
    userstats = user.fetch("userstats")

    Engines::Stats.new(
      external_user_id: user.fetch("id").to_s,
      external_username: user.fetch("username"),
      uploaded: Integer(userstats.fetch("uploaded")),
      downloaded: Integer(userstats.fetch("downloaded")),
      ratio: decimal(userstats["ratio"]),
      required_ratio: decimal(userstats["requiredratio"]),
      user_class: userstats["class"].presence,
      bonus_points: nil, seeding: nil, leeching: nil, snatched: nil, hit_and_runs: nil,
      uploads: nil, forum_posts: nil, torrent_comments: nil
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Engines::Error, "#{@site.name} sent a response Sherlock doesn't understand."
  end

  # The member's id from a profile link like https://gazellegames.net/user.php?id=123, or nil.
  def profile_user_id(uri)
    id = URI.decode_www_form(uri.query.to_s).to_h["id"].to_s
    id if uri.path == "/user.php" && id.match?(/\A[1-9]\d{0,9}\z/)
  end

  # Reads a member's profile with the instance key. Raises Engines::CheckNeeded when the member's opt-in
  # link isn't on it, before looking at anything else, or when the account is disabled or GGn won't show
  # the profile. Stats the profile hides come back nil. If GGn refuses the instance key itself, the whole
  # site pauses until the admin saves one that works.
  def fetch_profile(user_id, profile_code)
    profile = request(@site.instance_credential, "user", id: user_id)
    text = profile.values_at("profileText", "bbProfileText").join("\n")
    raise Engines::CheckNeeded, "The Sherlock link isn't on your #{@site.name} profile." unless Engines.opt_in_link?(text, profile_code)
    raise Engines::CheckNeeded, "#{@site.name} reports this account as disabled." if profile.dig("personal", "enabled") == false

    stats, personal, community = profile["stats"] || {}, profile["personal"] || {}, profile["community"] || {}
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
      hit_and_runs: lenient_count(personal["hnrs"]),
      user_class: personal["class"].presence,
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

  # Before the admin's key reads everyone: it must work, and reach the user request for its own profile.
  # Returns the key's own user id.
  def check_instance_key(api_key)
    id = request(api_key, "quick_user").fetch("id")
    request(api_key, "user", id:)
    id.to_s
  rescue Failure => error
    raise Engines::Error, "#{error.message} The key needs the User permission, so Sherlock can read profiles."
  end

  private
    def request(api_key, name, **params)
      uri = URI.join(@site.base_url, "/api.php")
      uri.query = URI.encode_www_form(request: name, **params)
      response = Engines::Http.get(uri, "X-API-Key" => api_key, site: @site)

      case response.code.to_i
      when 200
        body = parse(response.body)
        return body.fetch("response") if body["status"] == "success"

        raise Failure, "#{@site.name} said: #{message(body["error"], api_key)}"
      when 401, 403
        raise Engines::AccessDenied, "#{@site.name} returned #{response.code}. Your API key may be wrong, revoked, or missing the User permission."
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

    def message(text, api_key)
      text.to_s.scrub("").gsub(api_key, "[key]").squish.truncate(MESSAGE_LIMIT).presence || "no reason given"
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
end
