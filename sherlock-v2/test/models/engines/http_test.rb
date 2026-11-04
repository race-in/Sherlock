require "test_helper"

class Engines::HttpTest < ActiveSupport::TestCase
  setup { @resolver = Engines::Http.resolver }
  teardown { Engines::Http.resolver = @resolver }

  test "refuses hosts that resolve to private or local addresses" do
    %w[127.0.0.1 10.1.2.3 192.168.1.1 169.254.169.254 ::1 fd00::1 ::ffff:169.254.169.254 ::ffff:10.0.0.5 64:ff9b::a00:5].each do |ip|
      Engines::Http.resolver = ->(_) { [ ip ] }
      error = assert_raises(Engines::Error) { Engines::Http.get("https://tracker.example/ajax.php", site: nil) }
      assert_match "private address", error.message, ip
    end
  end

  test "refuses a host if any of its addresses is private" do
    Engines::Http.resolver = ->(_) { [ "93.184.216.34", "10.0.0.1" ] }
    assert_raises(Engines::Error) { Engines::Http.get("https://tracker.example/ajax.php", site: nil) }
  end

  test "sends headers passed without braces, the way every engine passes its key" do
    Engines::Http.resolver = ->(_) { [ "93.184.216.34" ] }
    sent = nil
    original = Net::HTTP.instance_method(:request)
    Net::HTTP.define_method(:request) { |request| sent = request; Net::HTTPOK.new("1.1", "200", "OK") }

    Engines::Http.get("https://tracker.example/ajax.php", "Authorization" => "token abc", site: nil)
    assert_equal "token abc", sent["Authorization"]
  ensure
    Net::HTTP.define_method(:request, original)
  end

  test "refuses plain http" do
    assert_raises(Engines::Error) { Engines::Http.get("http://tracker.example/ajax.php", site: nil) }
  end

  test "reports every request with its site, status and purpose, never the URL or host" do
    Engines::Http.resolver = ->(_) { [ "93.184.216.34" ] }
    original = Net::HTTP.instance_method(:request)
    Net::HTTP.define_method(:request) { |_request| Net::HTTPServiceUnavailable.new("1.1", "503", "Service Unavailable") }

    assert_event_reported("tracker.request", payload: { site: "redacted", status: "503", purpose: "test", key_owner: "member" }) do
      Engines::Http.get("https://tracker.example/ajax.php?action=index", site: sites(:redacted))
    end

    Net::HTTP.define_method(:request) { |_request| raise Net::OpenTimeout }
    assert_event_reported("tracker.request", payload: { site: "qui", status: "open_timeout" }) do
      assert_raises(Engines::Error) { Engines::Http.get("https://tracker.example/ajax.php", site: nil) }
    end
  ensure
    Net::HTTP.define_method(:request, original)
  end

  test "reports refused requests" do
    Engines::Http.resolver = ->(_) { [ "10.0.0.1" ] }
    assert_event_reported("tracker.request", payload: { site: "qui", status: "refused" }) do
      assert_raises(Engines::Error) { Engines::Http.get("https://tracker.example/ajax.php", site: nil) }
    end
  end

  test "spaces requests to a site across callers, and holds them back while the site is paused" do
    site = sites(:redacted)
    site.update!(request_interval: 10.seconds)
    waits = []
    Engines::Http.sleeper = ->(seconds) { waits << seconds }
    with_answers(Net::HTTPOK.new("1.1", "200", "OK")) do |sent|
      Current.set(tracker_purpose: "poll") { 2.times { Engines::Http.get("https://tracker.example/ajax.php", site: Site.find(site.id)) } }
      assert_equal 2, sent.size
    end
    assert_equal 1, waits.size, "the first request goes out at once, the second waits"
    assert_in_delta 10, waits.first, 0.5

    assert_raises(Engines::Busy, "a page doesn't wait 20 seconds") { Engines::Http.get("https://tracker.example/ajax.php", site:) }

    site.pause!(:admin)
    with_answers(Net::HTTPOK.new("1.1", "200", "OK")) do |sent|
      assert_event_reported("tracker.withheld", payload: { site: "redacted", reason: "paused", purpose: "poll" }) do
        Current.set(tracker_purpose: "poll") do
          assert_raises(Engines::Paused) { Engines::Http.get("https://tracker.example/ajax.php", site:) }
        end
      end
      assert_empty sent
    end
  end

  test "a 429 pauses the site for what it asked, at least five minutes" do
    site = sites(:redacted)
    limited = Net::HTTPTooManyRequests.new("1.1", "429", "Too Many Requests").tap { _1["Retry-After"] = "30" }
    with_answers(limited) { Engines::Http.get("https://tracker.example/ajax.php", site:) }

    site.reload
    assert site.paused_for_rate_limited?
    assert_in_delta 5.minutes.from_now, site.paused_until, 5
    assert_not Connection.pollable.exists?(site:)
  end

  test "five tracker errors in a row pause the site, an answer in between resets the count" do
    site = sites(:redacted)
    error = Net::HTTPServiceUnavailable.new("1.1", "503", "Service Unavailable")
    Current.set(tracker_purpose: "poll") do
      with_answers(error) { 4.times { Engines::Http.get("https://tracker.example/ajax.php", site:) } }
      with_answers(Net::HTTPOK.new("1.1", "200", "OK")) { Engines::Http.get("https://tracker.example/ajax.php", site:) }
      assert_not site.reload.paused?

      with_answers(error) { 5.times { Engines::Http.get("https://tracker.example/ajax.php", site:) } }
    end
    assert site.reload.paused_for_errors?
    assert_in_delta 1.hour.from_now, site.paused_until, 5
  end

  test "every request names its source and the admin's contact" do
    InstanceSetting.current.update!(tracker_contact: "admin@example.com")
    with_answers(Net::HTTPOK.new("1.1", "200", "OK")) do |sent|
      Engines::Http.get("https://tracker.example/ajax.php", site: sites(:redacted))
      assert_match Rails.configuration.x.source_url, sent.first["User-Agent"]
      assert_match "contact admin@example.com", sent.first["User-Agent"]
      assert_equal "admin@example.com", sent.first["From"]
    end
  end

  test "services that aren't trackers never get the tracker contact, and are reported by name" do
    InstanceSetting.current.update!(tracker_contact: "admin@example.com")
    with_answers(Net::HTTPOK.new("1.1", "200", "OK")) do |sent|
      assert_event_reported("tracker.request", payload: { site: "codeberg", status: "200" }) do
        Engines::Http.get("https://codeberg.org/api/v1/repos/whatstatus/sherlock-v2/tags", site: nil, service: "codeberg")
      end
      assert_match Rails.configuration.x.source_url, sent.first["User-Agent"]
      assert_no_match "admin@example.com", sent.first["User-Agent"]
      assert_nil sent.first["From"]
    end
  end

  test "only Engines::Http talks to the network, so nothing skips the gate" do
    others = Dir[Rails.root.join("app/**/*.rb")] - [ Rails.root.join("app/models/engines/http.rb").to_s ]
    assert_empty others.select { File.read(_1).match?(/Net::HTTP|URI\.open|Socket\.|TCPSocket/) }
  end

  private
    def with_answers(response)
      Engines::Http.resolver = ->(_) { [ "93.184.216.34" ] }
      sent = []
      original = Net::HTTP.instance_method(:request)
      Net::HTTP.define_method(:request) { |request| sent << request; response }
      yield sent
    ensure
      Net::HTTP.define_method(:request, original)
    end
end
