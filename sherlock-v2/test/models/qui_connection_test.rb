require "test_helper"

class QuiConnectionTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  MB = 1024**2
  RED = "https://flacsfor.me/abc/announce"
  OPS = "https://home.opsfet.ch/abc/announce"

  setup do
    @alice = users(:alice)
    @red = connections(:alice_redacted)
    @ops = @alice.connections.create!(site: sites(:orpheus), credential: "k", external_username: "a", external_user_id: "1")
  end

  test "counts cross-seeds per tracker: same files on another tracker, complete, seeding and announcing" do
    torrents = [
      # Same folder on Redacted and Orpheus.
      row(RED, "/data/album1", 100 * MB, uploaded: 5 * MB),
      row(OPS, "/data/album1", 100 * MB, uploaded: 7 * MB),
      # A hardlinked cross-seed: own folder, same size to the byte.
      row(RED, "/data/album2", 200 * MB, uploaded: 11 * MB),
      row(OPS, "/cross-seed/ops/album2", 200 * MB, uploaded: 13 * MB),
      # Small files of equal size in different folders aren't taken for the same files.
      row(RED, "/data/small-a", 1 * MB, uploaded: 1),
      row(OPS, "/data/small-b", 1 * MB, uploaded: 2),
      # Still downloading, so its Orpheus twin has nothing to cross-seed with.
      row(RED, "/data/album3", 300 * MB, progress: 0.5),
      row(OPS, "/data/album3", 300 * MB, uploaded: 17 * MB),
      # Unregistered on Orpheus, so the Redacted one isn't cross-seeded.
      row(RED, "/data/album4", 400 * MB, uploaded: 19 * MB),
      row(OPS, "/data/album4", 400 * MB, health: "unregistered"),
      # A tracker Sherlock doesn't know still counts as another tracker.
      row(RED, "/data/album5", 500 * MB, uploaded: 23 * MB),
      row("https://tracker.example.org/announce", "/data/album5", 500 * MB),
      # Twice on the same tracker isn't a cross-seed.
      row(RED, "/data/album6", 600 * MB, uploaded: 29 * MB),
      row(RED, "/data/album6", 600 * MB, uploaded: 31 * MB),
      # Paused isn't seeding, and alone it's no cross-seed either.
      row(OPS, "/data/album7", 700 * MB, state: "stoppedUP"),
      # Paused on Redacted, seeding on Orpheus: a paused cross-seed on both trackers.
      row(RED, "/data/album8", 800 * MB, state: "stoppedUP"),
      row(OPS, "/cross-seed/album8", 800 * MB, uploaded: 37 * MB)
    ]

    stub_qui("192.168.1.10" => { 1 => torrents }) do
      QuiConnection.connect!(user: @alice, url: "http://192.168.1.10:7476/", api_key: " qui-key ")
    end

    red = @red.cross_seed_snapshots.sole
    # Seeding on Redacted: album1, album2, small-a, album4, album5, album6 twice.
    assert_equal [ 7, 100 + 200 + 1 + 400 + 500 + 600 + 600 ], [ red.torrents, red.size / MB ]
    assert_equal [ 3, (100 + 200 + 500) * MB, (5 + 11 + 23) * MB ], [ red.cross_seeded, red.cross_seeded_size, red.cross_seeded_uploaded ]
    # album8 only. album3 is still downloading and album4 unregistered, so neither is a paused cross-seed.
    assert_equal 1, red.cross_seeded_paused

    ops = @ops.cross_seed_snapshots.sole
    # Seeding on Orpheus: album1, album2, small-b, album3, album8.
    assert_equal [ 5, 2, (100 + 200) * MB, (7 + 13) * MB, 1 ],
      [ ops.torrents, ops.cross_seeded, ops.cross_seeded_size, ops.cross_seeded_uploaded, ops.cross_seeded_paused ]

    qui = @alice.qui_connections.sole
    assert_equal [ "http://192.168.1.10:7476", "qui-key" ], [ qui.url, qui.credential ]
  end

  test "reads every page and only sends the key in the header" do
    page = Array.new(Qui::PAGE_SIZE) { row(RED, "/data/#{_1}", 20 * MB + _1) }
    stub_qui("qui.example.org" => { 3 => page + [ row(RED, "/data/last", MB) ] }) do |requests|
      @alice.qui_connections.create!(url: "https://qui.example.org/qui", credential: "qui-key", polled_at: Time.current)
      assert QuiConnection.poll!(@alice)
      assert_equal [ "/qui/api/instances", "/qui/api/instances/3/torrents", "/qui/api/instances/3/torrents" ], requests.map { _1[:uri].path }
      assert requests.all? { _1[:headers] == { "X-API-Key" => "qui-key" } && !_1[:local] && !_1[:uri].to_s.include?("qui-key") }
    end
    assert_equal Qui::PAGE_SIZE + 1, @red.cross_seed_snapshots.sole.torrents
  end

  test "a refused key saves nothing, and a failed poll keeps the error" do
    stub_qui_status(401) do
      error = assert_raises(Engines::AccessDenied) { QuiConnection.connect!(user: @alice, url: "http://qui.lan", api_key: "wrong") }
      assert_equal "qui refused the API key.", error.message
    end
    assert_empty @alice.reload.qui_connections

    stub_qui("qui.lan" => { 1 => [] }) { QuiConnection.connect!(user: @alice, url: "http://qui.lan", api_key: "right") }
    stub_qui_status(502) { assert_not QuiConnection.poll!(@alice) }
    qui = @alice.qui_connections.sole
    assert_equal "qui answered with HTTP 502. Check the address.", qui.error_message
    assert_not qui.is_key_refused, "a qui that's down keeps being tried"

    # Once the key is refused, qui isn't contacted again until the key is replaced.
    stub_qui_status(401) { QuiConnection.poll!(@alice) }
    assert qui.reload.is_key_refused
    stub_qui_status(200) do |requests|
      assert_not QuiConnection.poll!(@alice)
      assert_empty requests
    end
    assert_enqueued_jobs(0, only: PollQuiJob) { PollAllConnectionsJob.perform_now }
    stub_qui("qui.lan" => { 1 => [] }) { QuiConnection.connect!(user: @alice, url: "http://qui.lan", api_key: "new") }
    assert_not qui.reload.is_key_refused
    assert_enqueued_jobs(1, only: PollQuiJob) { PollAllConnectionsJob.perform_now }
  end

  test "only an admin's qui may be on a private network or plain http" do
    resolver = Engines::Http.resolver
    Engines::Http.resolver = ->(_) { [ "192.168.1.10" ] }
    error = assert_raises(Engines::Error) { QuiConnection.connect!(user: @alice, url: "https://qui.lan", api_key: "k") }
    assert_equal "qui.lan points to a private address, so Sherlock won't connect to it.", error.message
    error = assert_raises(Engines::Error) { QuiConnection.connect!(user: @alice, url: "http://qui.example.org", api_key: "k") }
    assert_equal "Only https addresses are allowed.", error.message
    assert_empty @alice.reload.qui_connections

    stub_qui("qui.lan" => { 1 => [] }) do |requests|
      QuiConnection.connect!(user: users(:admin), url: "http://qui.lan", api_key: "k")
      assert requests.any? && requests.all? { _1[:local] }
    end
  ensure
    Engines::Http.resolver = resolver
  end

  test "several quis add up per tracker, and cross-seeds only count within one qBittorrent" do
    # Both quis number their instance 1. The same folder on two machines isn't the same files.
    stub_qui("qui-a.lan" => { 1 => [ row(RED, "/data/album1", 100 * MB, uploaded: 3 * MB), row(OPS, "/data/album1", 100 * MB) ] },
             # Instance 2 is a qBittorrent qui can't reach; it's skipped instead of failing the poll.
             "qui-b.lan" => { 1 => [ row(RED, "/data/album2", 200 * MB, uploaded: 5 * MB), row(OPS, "/data/album1", 100 * MB) ], 2 => :disconnected }) do
      QuiConnection.connect!(user: @alice, url: "http://qui-a.lan", api_key: "key-a")
      QuiConnection.connect!(user: @alice, url: "http://qui-b.lan", api_key: "key-b")
    end
    assert_equal [ "http://qui-a.lan", "http://qui-b.lan" ], @alice.qui_connections.order(:id).pluck(:url)

    red = @red.cross_seed_snapshots.order(:id).last
    assert_equal [ 2, 300 * MB, 8 * MB, 1, 100 * MB ], [ red.torrents, red.size, red.uploaded, red.cross_seeded, red.cross_seeded_size ]
    assert_equal [ 2, 1 ], @ops.cross_seed_snapshots.order(:id).last.then { [ _1.torrents, _1.cross_seeded ] }
    # Each qui's own totals: qui-a has the cross-seeded pair, qui-b two lone torrents.
    assert_equal [ [ 2, 2, 0 ], [ 2, 0, 0 ] ], @alice.qui_connections.order(:id).map { [ _1.seeding, _1.cross_seeded, _1.cross_seeded_paused ] }

    # Adding an address again replaces its key instead of adding it twice.
    stub_qui("qui-a.lan" => { 1 => [] }, "qui-b.lan" => { 1 => [] }) { QuiConnection.connect!(user: @alice, url: "http://qui-a.lan/", api_key: "new-key") }
    assert_equal [ "new-key", "key-b" ], @alice.qui_connections.order(:id).map(&:credential)

    # One failing qui saves nothing, so the other's torrents don't show up as the whole count.
    assert_no_difference -> { CrossSeedSnapshot.count } do
      stub_qui("qui-a.lan" => { 1 => [ row(RED, "/data/x", MB) ] }, "qui-b.lan" => 502) { assert_not QuiConnection.poll!(@alice) }
    end
    assert_equal [ nil, "qui answered with HTTP 502. Check the address." ], @alice.qui_connections.order(:id).map(&:error_message)
  end

  private
    def row(tracker, content_path, size, uploaded: 0, progress: 1, state: "stalledUP", health: nil)
      { "tracker" => tracker, "content_path" => content_path, "size" => size, "uploaded" => uploaded,
        "progress" => progress, "state" => state, "tracker_health" => health }.compact
    end
end
