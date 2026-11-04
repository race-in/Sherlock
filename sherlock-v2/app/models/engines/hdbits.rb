# HDBits. The API takes POST requests with the username and passkey in a JSON body, so the
# connection's credential is that pair as JSON (see Site#credential_from). It answers HTTP 200 with
# {"status": 0, "data": {...}} on success, or another status and a "message": 4 and 5 mean the login
# was refused. /api/user reports the account id, bytes and bonus points, and nothing else. The
# passkey is the one in torrent announce URLs, so HDBits is a passkey site and starts switched off.
class Engines::Hdbits
  REFUSED = [ 4, 5 ].freeze
  MESSAGE_LIMIT = 200

  def initialize(site)
    @site = site
  end

  def fetch(credential)
    username, passkey = JSON.parse(credential).values_at("username", "passkey")
    data = request(username, passkey)
    uploaded, downloaded = Integer(data.fetch("uploaded")), Integer(data.fetch("downloaded"))

    Engines::Stats.new(
      external_user_id: data.fetch("id").to_s,
      external_username: username,
      uploaded:,
      downloaded:,
      ratio: (BigDecimal(uploaded).div(downloaded, 10).round(4) if downloaded.positive?),
      bonus_points: BigDecimal(data.fetch("bonus").to_s),
      required_ratio: nil, seeding: nil, leeching: nil, snatched: nil, hit_and_runs: nil, user_class: nil,
      uploads: nil, forum_posts: nil, torrent_comments: nil
    )
  rescue KeyError, TypeError, ArgumentError, JSON::ParserError
    raise Engines::Error, "#{@site.name} sent a response Sherlock doesn't understand."
  end

  private
    def request(username, passkey)
      response = Engines::Http.post(URI.join(@site.base_url, "/api/user"), { username:, passkey: }, site: @site)

      case response.code.to_i
      when 200
        body = JSON.parse(response.body)
        return body.fetch("data") if body["status"] == 0

        text = body["message"].to_s.scrub("").gsub(passkey.to_s, "[key]").squish.truncate(MESSAGE_LIMIT).presence || "no reason given"
        raise REFUSED.include?(body["status"]) ? Engines::AccessDenied : Engines::Error, "#{@site.name} said: #{text}"
      when 401, 403
        raise Engines::AccessDenied, "#{@site.name} returned #{response.code}. Your username or passkey may be wrong."
      when 429
        raise Engines::RateLimited, "#{@site.name} asked us to slow down."
      else
        raise Engines::Error, "#{@site.name} returned HTTP #{response.code}."
      end
    end
end
