# Anthelion. A Gazelle fork with its own api.php grammar: a poll is one
# GET api.php?action=user&method=getuserinfo&type=username&user=<name>&api_key=<key>, so the
# credential is the username and key as JSON (see Site#credential_from). The key can only go in the
# query; Engines::Http reports the host, never the URL. It answers {"status": "success", "response":
# {...}} or {"status": "failure", "error": "..."}, a bad key with 403 "Unrecognized key". Numbers may
# come as text. The response also carries the IRC key, email and inviter; Sherlock reads none of them.
class Engines::Anthelion
  MESSAGE_LIMIT = 200

  def initialize(site)
    @site = site
  end

  def fetch(credential)
    username, api_key = JSON.parse(credential).values_at("username", "api_key")
    user = request(username, api_key)
    uploaded, downloaded = Integer(user.fetch("Uploaded")), Integer(user.fetch("Downloaded"))

    Engines::Stats.new(
      external_user_id: user.fetch("ID").to_s,
      external_username: user.fetch("Username"),
      uploaded:,
      downloaded:,
      ratio: (BigDecimal(uploaded).div(downloaded, 10).round(4) if downloaded.positive?),
      bonus_points: (BigDecimal(user["Orbs"].to_s) unless user["Orbs"].nil?),
      seeding: count(user["SeedCount"]),
      snatched: count(user["Snatched"]),
      hit_and_runs: count(user["HnR"]),
      uploads: count(user["Uploads"]),
      forum_posts: count(user["ForumPosts"]),
      user_class: user["Class"].presence,
      required_ratio: nil, leeching: nil, torrent_comments: nil
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError, JSON::ParserError
    raise Engines::Error, "#{@site.name} sent a response Sherlock doesn't understand."
  end

  private
    def request(username, api_key)
      uri = URI.join(@site.base_url, "/api.php")
      uri.query = URI.encode_www_form(action: "user", method: "getuserinfo", type: "username", user: username, api_key:)
      response = Engines::Http.get(uri, site: @site)

      case response.code.to_i
      when 200, 403
        body = parse(response.body)
        return body.fetch("response") if body["status"] == "success" && body["response"].is_a?(Hash)

        error = message(body["error"], api_key)
        raise response.code.to_i == 403 ? Engines::AccessDenied : Engines::Error, "#{@site.name} said: #{error}"
      when 401
        raise Engines::AccessDenied, "#{@site.name} returned 401. Your API key may be wrong or revoked."
      when 429
        raise Engines::RateLimited, "#{@site.name} asked us to slow down."
      else
        raise Engines::Error, "#{@site.name} returned HTTP #{response.code}."
      end
    end

    def parse(body)
      JSON.parse(body).tap { raise JSON::ParserError unless _1.is_a?(Hash) }
    rescue JSON::ParserError
      raise Engines::Error, "#{@site.name} sent a response that isn't JSON."
    end

    def message(text, api_key)
      text.to_s.scrub("").gsub(api_key.to_s, "[key]").squish.truncate(MESSAGE_LIMIT).presence || "no reason given"
    end

    def count(value)
      Integer(value) unless value.nil?
    end
end
