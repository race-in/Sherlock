require "net/http"
require "resolv"

# The only way Sherlock talks to a tracker. Base URLs come from the sites table, never from users,
# but the host is still resolved first and refused if it points at a private or local address, and
# the connection is made to that same checked address.
#
# Every tracker request first takes a slot from its site (Site#reserve_request!), so a site never gets
# more than one request per request_interval from all jobs and pages together, and nothing while it's
# paused. The tracker's answer can pause it (Site#tracker_answered).
#
# site: nil is for services that aren't trackers, like a user's qui or Codeberg for update checks,
# named by service: in metrics. They don't get the tracker contact. local: true is for services an
# admin runs themselves: it allows plain http and private addresses, since those usually live on the
# admin's own network.
class Engines::Http
  TIMEOUT = 15
  # A whole request, slow drip or not, and the most of an answer Sherlock reads. A qui page of 2000
  # torrents is a few MB; trackers send a few KB.
  DEADLINE = 60
  MAX_BODY = 32.megabytes
  class TooLarge < Engines::Error; end
  class TookTooLong < Timeout::Error; end
  # How long a request may wait for its site's next slot, in seconds, by why it's sent. Polls run in
  # jobs and can wait. The rest run while someone watches a page.
  MAX_WAIT = { "poll" => 60, "check" => 5, "test" => 5, "instance_key" => 5 }.freeze
  EMAIL = /\A[^@\s]+@[^@\s]+\z/
  BLOCKED_RANGES = %w[
    0.0.0.0/8 10.0.0.0/8 100.64.0.0/10 127.0.0.0/8 169.254.0.0/16 172.16.0.0/12 192.0.0.0/24
    192.168.0.0/16 198.18.0.0/15 224.0.0.0/4 240.0.0.0/4 ::/128 ::1/128 64:ff9b::/96 fc00::/7 fe80::/10 ff00::/8
  ].map { IPAddr.new(_1) }

  # Swapped in tests so they never touch DNS or wait.
  mattr_accessor :resolver, default: ->(host) { Resolv.getaddresses(host) }
  mattr_accessor :sleeper, default: ->(seconds) { sleep(seconds) }

  # Callers pass headers without braces, like get(url, "Authorization" => key, site: @site). Ruby reads
  # those as keyword arguments, so they arrive in string_headers.
  def self.get(url, headers = {}, site:, local: false, service: "qui", **string_headers)
    new(URI(url), site:, local:, service:).get(headers.merge(string_headers))
  end

  # For APIs that take the credentials in a JSON body, like HDBits.
  def self.post(url, body, headers = {}, site:)
    new(URI(url), site:).post(body, headers)
  end

  # Why requests go out right now: "poll" in poll jobs, set with Current.set(tracker_purpose:), and
  # "test" when nobody said, which waits the least.
  def self.purpose
    Current.tracker_purpose || "test"
  end

  # Tells tracker staff that Sherlock is asking, where its code is, and how to reach whoever runs it.
  # The admin page shows the same string, so it can't drift from what's sent.
  def self.user_agent(contact = InstanceSetting.tracker_contact)
    details = [ "+#{Rails.configuration.x.source_url}", ("contact #{contact}" if contact.present?) ]
    "Sherlock/#{Rails.configuration.x.version} (#{details.compact.join("; ")})"
  end

  def initialize(uri, site:, local: false, service: "qui")
    raise Engines::Error, "Only http and https URLs are allowed." if local && !uri.is_a?(URI::HTTP)
    raise Engines::Error, "Only https addresses are allowed." unless local || uri.is_a?(URI::HTTPS)
    @uri = uri
    @site = site
    @local = local
    @service = service
  end

  def get(headers)
    perform(Net::HTTP::Get.new(@uri, headers.merge(identity, "Accept" => "application/json")))
  end

  def post(body, headers)
    request = Net::HTTP::Post.new(@uri, headers.merge(identity, "Accept" => "application/json", "Content-Type" => "application/json"))
    request.body = body.to_json
    perform(request)
  end

  private
    def identity
      contact = InstanceSetting.tracker_contact if @site
      { "User-Agent" => self.class.user_agent(contact), "From" => (contact if contact.to_s.match?(EMAIL)) }.compact
    end

    def perform(request)
      waited = take_slot
      send_request(request, waited)
    end

    # Waits for the site's slot, or raises Engines::Paused or Engines::Busy without sending anything.
    # The admin's own key test still goes out while the site waits for a working key.
    def take_slot
      return 0 unless @site

      wait = @site.reserve_request!(within: MAX_WAIT.fetch(purpose), for_key_test: purpose == "instance_key")
      self.class.sleeper.call(wait) if wait.positive?
      wait
    rescue Engines::Withheld => error
      Rails.event.notify("tracker.withheld", site: label, reason: error.is_a?(Engines::Paused) ? "paused" : "busy", purpose:)
      raise
    end

    # Every request is reported as tracker.request with the site, the HTTP status (or the network
    # error, like "open_timeout"), why it was sent, and how long it waited and took. Never the URL, the
    # host or headers: they carry the key, and for qui the user's own server.
    def send_request(request, waited)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status = "refused"
      response = Timeout.timeout(DEADLINE, TookTooLong) { client.request(request) { read_capped(_1) } }
      status = response.code
      @site&.tracker_answered(response)
      response
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, EOFError => error
      status = error.class.name.demodulize.underscore
      @site&.tracker_failed
      raise Engines::Error, "#{@uri.host} did not respond (#{error.class.name.demodulize})."
    rescue TooLarge
      status = "too_large"
      raise
    ensure
      Rails.event.notify("tracker.request", site: label, status:, purpose:, key_owner: @site&.key_owner || "member",
        wait: waited, duration: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    end

    # Reads the answer in chunks, after any gzip is unpacked, and stops past MAX_BODY.
    def read_capped(response)
      body = String.new
      response.read_body do |chunk|
        body << chunk
        raise TooLarge, "#{@uri.host} sent more than #{MAX_BODY / 1.megabyte} MB." if body.bytesize > MAX_BODY
      end
      response.body = body
    end

    def purpose
      self.class.purpose
    end

    def label
      @site&.slug || @service
    end

    def client
      Net::HTTP.new(@uri.host, @uri.port).tap do |http|
        http.ipaddr = checked_address
        http.use_ssl = @uri.is_a?(URI::HTTPS)
        http.open_timeout = TIMEOUT
        http.read_timeout = TIMEOUT
      end
    end

    def checked_address
      addresses = resolver.call(@uri.host)
      raise Engines::Error, "#{@uri.host} could not be found." if addresses.empty?

      # native turns an IPv4-mapped IPv6 address (::ffff:10.0.0.5) into the IPv4 address it reaches.
      ips = addresses.map { IPAddr.new(_1).native }
      if !@local && ips.any? { |ip| BLOCKED_RANGES.any? { _1.include?(ip) } }
        raise Engines::Error, "#{@uri.host} points to a private address, so Sherlock won't connect to it."
      end
      ips.first.to_s
    end
end
