# BroadcasTheNet. A JSON-RPC API (https://apidocs.broadcasthe.net/v1/user/userInfo/): a POST of
# {"id", "method", "params"} that answers HTTP 200 with {"result": {...}} or {"result": null,
# "error": {"code", "message"}}. userInfo sends every number as a string. The key allows 150 calls an
# hour. BTN only answers from IP addresses the user approved on the site, so the first call from a new
# server fails with -32004 until they do; that's a passing error, not a bad key.
class Engines::Btn
  REFUSED = [ -32001, -32003 ].freeze # invalid key, account disabled
  RATE_LIMITED = -32002
  MESSAGE_LIMIT = 200

  def initialize(site)
    @site = site
  end

  def fetch(api_key)
    user = call(api_key, "userInfo")
    uploaded, downloaded = Integer(user.fetch("Upload")), Integer(user.fetch("Download"))

    Engines::Stats.new(
      external_user_id: user.fetch("UserID").to_s,
      external_username: user.fetch("Username"),
      uploaded:,
      downloaded:,
      ratio: (BigDecimal(uploaded).div(downloaded, 10).round(4) if downloaded.positive?),
      bonus_points: BigDecimal(user.fetch("Bonus").to_s),
      snatched: Integer(user.fetch("Snatches")),
      hit_and_runs: Integer(user.fetch("HnR")),
      user_class: user["Class"].presence,
      required_ratio: nil, seeding: nil, leeching: nil, uploads: nil, forum_posts: nil, torrent_comments: nil
    )
  rescue KeyError, TypeError, ArgumentError, NoMethodError
    raise Engines::Error, "#{@site.name} sent a response Sherlock doesn't understand."
  end

  private
    def call(api_key, method)
      response = Engines::Http.post(URI.join(@site.base_url, "/"), { id: 1, method:, params: { key: api_key } }, site: @site)
      raise Engines::Error, "#{@site.name} returned HTTP #{response.code}." unless response.code.to_i == 200

      body = JSON.parse(response.body)
      return body.fetch("result") unless body["error"]

      code = body["error"]["code"]
      text = body["error"]["message"].to_s.scrub("").gsub(api_key, "[key]").squish.truncate(MESSAGE_LIMIT).presence || "no reason given"
      if code == RATE_LIMITED
        @site.rate_limited!(300)
        raise Engines::RateLimited, "#{@site.name} said: #{text}"
      end
      raise REFUSED.include?(code) ? Engines::AccessDenied : Engines::Error, "#{@site.name} said: #{text}"
    rescue JSON::ParserError
      raise Engines::Error, "#{@site.name} sent a response that isn't JSON."
    end
end
