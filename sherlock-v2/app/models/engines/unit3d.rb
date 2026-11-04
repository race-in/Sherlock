# UNIT3D (https://github.com/HDInnovations/UNIT3D), which runs Aither, Blutopia and many others. A poll is
# one GET /api/user with the key as a Bearer token; the API guard also takes ?api_token=, but that would
# put the key in a URL. The answer is UserResource: username, group, uploaded, downloaded, ratio, buffer,
# seeding, leeching, seedbonus and hit_and_runs, with no user ID, so the username stands in for it, as
# UNIT3D's own profile URLs do.
# Stock UNIT3D sends uploaded and downloaded rounded for display, like "1.23 TiB", so they only move in
# steps of 0.01 of their unit. Some sites patch them to whole bytes, and LST wraps everything in "data";
# both are read too. A missing or broken key answers 401 {"message": "Unauthenticated."}. A banned account
# answers 200 with only a message. The API allows 30 requests a minute per account.
class Engines::Unit3d
  UNITS = { "B" => 0, "KiB" => 1, "MiB" => 2, "GiB" => 3, "TiB" => 4, "PiB" => 5 }.freeze
  SIZE = /\A(?<value>\d+(?:\.\d+)?)[[:space:]]*(?<unit>#{UNITS.keys.join("|")})\z/
  MESSAGE_LIMIT = 200

  def initialize(site)
    @site = site
  end

  def fetch(api_key)
    user = request(api_key)

    Engines::Stats.new(
      external_user_id: user.fetch("username"),
      external_username: user.fetch("username"),
      uploaded: bytes(user.fetch("uploaded")),
      downloaded: bytes(user.fetch("downloaded")),
      ratio: ratio(user["ratio"]),
      bonus_points: (BigDecimal(user["seedbonus"].to_s) unless user["seedbonus"].nil?),
      seeding: count(user["seeding"]),
      leeching: count(user["leeching"]),
      hit_and_runs: count(user["hit_and_runs"]),
      user_class: user["group"].presence,
      required_ratio: nil, snatched: nil, uploads: nil, forum_posts: nil, torrent_comments: nil
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Engines::Error, "#{@site.name} sent a response Sherlock doesn't understand."
  end

  private
    def request(api_key)
      response = Engines::Http.get(URI.join(@site.base_url, "/api/user"), "Authorization" => "Bearer #{api_key}", site: @site)

      case response.code.to_i
      when 200
        body = parse(response.body)
        body = body["data"] if body["data"].is_a?(Hash)
        return body if body.key?("username")
        raise Engines::AccessDenied, "#{@site.name} said: #{message(body["message"], api_key)}" if body.key?("message")

        raise Engines::Error, "#{@site.name} sent a response Sherlock doesn't understand."
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
      text.to_s.scrub("").gsub(api_key, "[key]").squish.truncate(MESSAGE_LIMIT).presence || "no reason given"
    end

    # Whole bytes as a number or digits, or a display size like "1.23 TiB". Anything else raises.
    def bytes(value)
      return Integer(value) unless value.is_a?(String) && (size = SIZE.match(value.strip))

      (BigDecimal(size[:value]) * (1024**UNITS.fetch(size[:unit]))).round
    end

    # "∞" when nothing was downloaded yet; Sherlock leaves that ratio out rather than store a number.
    def ratio(value)
      BigDecimal(value.to_s) unless value.nil? || value == "∞"
    end

    def count(value)
      Integer(value) unless value.nil?
    end
end
