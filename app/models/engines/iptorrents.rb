require "nokogiri"
# IPTorrents has no public stats API. It uses the member's authenticated browser
# session, so Sherlock stores only the explicitly supplied session cookies.
class Engines::Iptorrents
  COOKIE_NAMES = %w[uid pass cf_clearance].freeze
  PROFILE_PATH = "/user.php"

  def initialize(site)
    @site = site
  end

  def fetch(cookie_string)
    cookies = parse_cookies(cookie_string)
    home = request("/", cookies)
    user_id = Nokogiri::HTML(home).at_css('a[href^="/u/"]')&.[]("href")&.match(%r{\A/u/(\d+)\z})&.captures&.first
    raise Engines::AccessDenied, "IPTorrents couldn't find a signed-in account. Check that the uid and pass cookies are current." unless user_id

    profile = request("#{PROFILE_PATH}?u=#{user_id}", cookies)
    stats = parse_stats(profile)
    username = Nokogiri::HTML(profile).at_css("title")&.text&.sub(/\s*-\s*IPTorrents.*\z/i, "")&.strip
    raise Engines::Error, "IPTorrents did not return a recognizable profile." if username.blank?

    Engines::Stats.new(
      external_user_id: user_id, external_username: username,
      uploaded: stats.fetch(:uploaded), downloaded: stats.fetch(:downloaded),
      ratio: stats[:ratio], required_ratio: nil, bonus_points: nil,
      seeding: nil, leeching: nil, snatched: nil, hit_and_runs: nil,
      user_class: nil, uploads: nil, forum_posts: nil, torrent_comments: nil
    )
  rescue KeyError, ArgumentError, TypeError
    raise Engines::Error, "IPTorrents sent profile statistics Sherlock couldn't understand."
  end

  private
    def parse_cookies(value)
      pairs = value.to_s.split(";").filter_map do |part|
        name, content = part.strip.split("=", 2)
        [name, content] if COOKIE_NAMES.include?(name) && content.present? && content.match?(/\\A[\\w%+\\/=.-]+\\z/)
      end
      cookies = pairs.to_h
      raise Engines::AccessDenied, "Enter the IPTorrents uid and pass cookies copied from your signed-in browser." unless %w[uid pass].all? { cookies[_1].present? }
      cookies
    end

    def request(path, cookies)
      uri = URI.join(@site.base_url, path)
      response = Engines::Http.get(uri, { "Cookie" => cookies.map { |k, v| "#{k}=#{v}" }.join("; "),
        "Accept" => "text/html,application/xhtml+xml" }, site: @site)
      case response.code.to_i
      when 200
        body = response.body.to_s
        if body.match?(/cloudflare|just a moment|attention required|turnstile/i) && !body.match?(/ipx-stat__value/i)
          raise Engines::AccessDenied, "IPTorrents returned a browser security challenge. Refresh your browser cookies, including cf_clearance if present."
        end
        body
      when 401, 403, 302, 303
        raise Engines::AccessDenied, "IPTorrents rejected the session cookies. Copy fresh uid and pass cookies from a signed-in browser."
      when 429
        raise Engines::RateLimited, "IPTorrents asked Sherlock to slow down."
      else
        raise Engines::Error, "IPTorrents returned HTTP #{response.code}."
      end
    end

    def parse_stats(html)
      document = Nokogiri::HTML(html)
      values = {}
      { uploaded: "up", downloaded: "down", ratio: "ratio" }.each do |key, suffix|
        card = document.at_css(".ipx-stat.upf-stat--#{suffix}")
        next unless card
        node = key == :ratio ? card.at_css(".ipx-stat__value") : card.at_css(".ipx-stat__sub")
        raw = node&.text&.strip
        next if raw.blank?
        values[key] = key == :ratio ? BigDecimal(raw.delete(",")) : Integer(raw.delete(",").sub(/\s+[A-Z]+\z/i, ""))
      end
      raise Engines::Error, "IPTorrents profile is missing uploaded or downloaded totals." unless values[:uploaded] && values[:downloaded]
      values[:ratio] ||= (BigDecimal(values[:uploaded]).div(values[:downloaded], 6) if values[:downloaded].positive?)
      values
    end
    def strip_html(value)
      CGI.unescapeHTML(value.to_s.gsub(/<[^>]*>/, " ").squish)
    end
end
