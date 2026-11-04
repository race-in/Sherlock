# AnimeBytes. A poll is one GET /api/stats/personal with the key as a Bearer token (a bare key works
# too). It answers {"success": true, "class", "yen", "hnrs", "upload", "download", "torrents",
# "tracker"}, or {"success": false, "error": "..."}: 401 without a key, 403 "Incorrect token" with a
# bad one. It names no account, so the credential is the username the user typed and the key, as
# JSON (see Site#credential_from), and the username stands in for the user ID. upload and download
# come as raw and account; account is the credited amount the ratio is worked out from.
class Engines::Animebytes
  MESSAGE_LIMIT = 200

  def initialize(site)
    @site = site
  end

  def fetch(credential)
    username, api_key = JSON.parse(credential).values_at("username", "api_key")
    stats = request(api_key)
    uploaded = Integer(stats.fetch("upload").fetch("account"))
    downloaded = Integer(stats.fetch("download").fetch("account"))
    tracker = stats["tracker"] || {}

    Engines::Stats.new(
      external_user_id: username.presence || raise(KeyError),
      external_username: username,
      uploaded:,
      downloaded:,
      ratio: (BigDecimal(uploaded).div(downloaded, 10).round(4) if downloaded.positive?),
      bonus_points: (BigDecimal(stats.dig("yen", "current").to_s) unless stats.dig("yen", "current").nil?),
      seeding: count(tracker["seeding"]),
      leeching: count(tracker["leeching"]),
      snatched: count(tracker["snatched"]),
      hit_and_runs: count(stats.dig("hnrs", "active")),
      uploads: count(stats.dig("torrents", "uploaded")),
      user_class: stats["class"].presence,
      required_ratio: nil, forum_posts: nil, torrent_comments: nil
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError, JSON::ParserError
    raise Engines::Error, "#{@site.name} sent a response Sherlock doesn't understand."
  end

  private
    def request(api_key)
      response = Engines::Http.get(URI.join(@site.base_url, "/api/stats/personal"), "Authorization" => "Bearer #{api_key}", site: @site)

      case response.code.to_i
      when 200
        body = parse(response.body)
        return body if body["success"] == true

        raise Engines::Error, "#{@site.name} said: #{message(body["error"], api_key)}"
      when 401, 403
        raise Engines::AccessDenied, "#{@site.name} returned #{response.code}. Your API key may be wrong or revoked."
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
