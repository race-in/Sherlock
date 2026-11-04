require "test_helper"

class ConnectionTest < ActiveSupport::TestCase
  test "connect saves the connection and first snapshot only after the tracker accepts the key" do
    user = users(:alice)
    stub_redacted_success do
      assert_difference -> { Snapshot.count } => 1 do
        connection = Connection.connect!(user:, site: sites(:orpheus), api_key: "new-key")
        assert_equal "dr4g0n", connection.external_username
        assert_equal "new-key", connection.reload.credential
        assert_equal [ 29, 863, 13 ], connection.snapshots.last.values_at(:uploads, :forum_posts, :torrent_comments)
        assert_equal "api", connection.snapshots.last.source
      end
    end

    stub_tracker({ "index" => [ 401, "" ] }) do
      assert_no_difference -> { Connection.count } do
        assert_raises(Engines::AccessDenied) { Connection.connect!(user: users(:bob), site: sites(:orpheus), api_key: "x") }
      end
    end
  end

  test "a granted tracker isn't contacted once the grant is taken back, and an off tracker for nobody" do
    hdbits = users(:alice).connections.create!(site: sites(:hdbits), credential: { username: "a", passkey: "p" }.to_json,
      external_username: "a", external_user_id: "1")
    admin_hdbits = users(:admin).connections.create!(site: sites(:hdbits), credential: { username: "b", passkey: "q" }.to_json,
      external_username: "b", external_user_id: "2")
    grant = users(:alice).site_grants.create!(site: sites(:hdbits))
    assert_includes Connection.pollable, hdbits
    # Bob's grant doesn't count for Alice.
    grant.destroy!
    users(:bob).site_grants.create!(site: sites(:hdbits))
    assert_not_includes Connection.pollable, hdbits
    assert_includes Connection.pollable, admin_hdbits, "admins use every granted tracker"
    assert_includes Connection.pollable, connections(:alice_redacted)
    assert_equal Connection.pollable.select { _1.site.available_to?(_1.user) }, Connection.pollable.to_a, "pollable matches available_to?"

    sites(:hdbits).update!(availability: :off)
    assert_not_includes Connection.pollable, admin_hdbits
    sites(:hdbits).update!(availability: :everyone)
    assert_includes Connection.pollable, hdbits
    sites(:hdbits).update!(availability: :granted)

    stub_tracker_post([ 500, "" ]) do |requests|
      assert_not hdbits.poll!
      assert_raises(Engines::Error) { hdbits.replace_key!("other") }
      assert_empty requests
    end
    assert_equal "HDBits isn't available to you on this Sherlock.", hdbits.reload.error_message
  end

  test "keys are encrypted at rest" do
    raw = Connection.connection.select_value("SELECT credential FROM connections WHERE id = #{connections(:alice_redacted).id}")
    assert_not_includes raw, "alice-secret-key"
    assert_equal "alice-secret-key", connections(:alice_redacted).credential
  end

  test "charts draw the picked color, or the site's until one is picked" do
    connection = connections(:alice_redacted)
    assert_equal "#8e90c8", connection.display_color

    connection.update!(color: "#1F7FA6")
    assert_equal "#1f7fa6", connection.reload.display_color
  end

  test "a picked color must be a six digit hex color" do
    connection = connections(:alice_redacted)
    assert_raises(ActiveRecord::RecordInvalid) { connection.update!(color: "blue") }
    assert_raises(ActiveRecord::RecordInvalid) { connection.update!(color: "#12345") }
    assert_not connection.reload.color
  end

  test "unsupported sites and sites switched off by the admin can't be connected" do
    assert_raises(Engines::Error) { Connection.connect!(user: users(:bob), site: sites(:avistaz), api_key: "x") }
    assert_raises(Engines::Error) { Connection.connect!(user: users(:bob), site: sites(:hdbits), api_key: "x") }
  end

  test "three failed polls in a row mark the connection failing, a success resets it" do
    connection = connections(:alice_redacted)
    stub_tracker({ "index" => [ 500, "" ] }) do
      2.times { assert_not connection.poll! }
      assert connection.reload.ok?
      connection.poll!
      assert connection.reload.failing?
      assert_equal 3, connection.failure_count
    end

    stub_redacted_success { assert connection.poll! }
    connection.reload
    assert connection.ok?
    assert_equal 0, connection.failure_count
    assert_nil connection.error_message
  end

  test "polls are counted by site and result for /metrics" do
    polls = ->(result) { Yabeda.sherlock.polls_total.values[{ site: "redacted", result: }]&.value.to_i }
    connection = connections(:alice_redacted)

    assert_difference -> { polls.("succeeded") } => 1, -> { polls.("failed") } => 2 do
      stub_tracker({ "index" => [ 500, "" ] }) { 2.times { connection.poll! } }
      stub_redacted_success { connection.poll! }
    end
  end

  test "a refused key goes straight to needs key and leaves polling" do
    connection = connections(:alice_redacted)
    stub_tracker({ "index" => [ 200, { status: "failure", error: "invalid token" }.to_json ] }) { connection.poll! }
    assert connection.reload.needs_key?
    assert_not Connection.pollable.include?(connection)
  end

  test "replacing a key keeps the old one when the tracker refuses the new one" do
    connection = connections(:alice_redacted)
    stub_tracker({ "index" => [ 401, "" ] }) do
      assert_raises(Engines::AccessDenied) { connection.replace_key!("bad-key") }
    end
    assert_equal "alice-secret-key", connection.reload.credential

    connection.update!(status: :needs_key)
    stub_redacted_success { connection.replace_key!("good-key") }
    assert_equal "good-key", connection.reload.credential
    assert connection.ok?
  end

  test "pollable skips paused connections and disabled users" do
    assert_includes Connection.pollable, connections(:bob_redacted)
    connections(:bob_redacted).pause!
    assert_not_includes Connection.pollable, connections(:bob_redacted)
    connections(:bob_redacted).resume!
    users(:bob).disable!
    assert_not_includes Connection.pollable, connections(:bob_redacted)
  end

  test "switching a site to the instance key deletes members' keys and asks for their link, and keeps their history" do
    site = sites(:redacted)
    bob = connections(:bob_redacted)
    snapshots = bob.snapshots.count
    stub_redacted_success { site.use_instance_key!("admin-key") }

    assert site.reload.instance_key?
    assert_equal "admin-key", site.instance_credential
    bob.reload
    assert_nil bob.credential
    assert bob.needs_check?
    assert_match(/\A[a-z0-9]{10}\z/, bob.profile_code)
    assert_equal snapshots, bob.snapshots.count
    assert_not Connection.pollable.exists?(bob.id)

    owner = connections(:alice_redacted).reload
    assert owner.is_key_owner?, "the key is alice's own (user 469), so it reads her account"
    assert_nil owner.credential
    assert_nil owner.profile_code
    assert owner.ok?
    assert Connection.pollable.exists?(owner.id)
  end

  test "the key's own account reads with the key, with every stat and no link, until a key from another account replaces it" do
    site = sites(:redacted)
    connections(:alice_redacted).update!(external_user_id: "999")
    stub_redacted_success { site.use_instance_key!("admin-key") }
    connection = stub_redacted_success { Connection.connect_key_owner!(user: users(:admin), site:) }

    assert connection.is_key_owner?
    assert_equal "469", connection.external_user_id
    assert Connection.pollable.exists?(connection.id)
    stub_redacted_success do |requests|
      assert connection.poll!, "user.json has no opt-in link, and the key's own account needs none"
      assert_includes requests.map { URI.decode_www_form(_1[:uri].query).to_h["action"] }, "index", "read like a member's own key, not as a profile"
    end
    assert_equal 2, connection.snapshots.count

    index = JSON.parse(file_fixture("redacted/index.json").read).tap { _1["response"]["id"] = 999 }
    stub_tracker({ "index" => [ 200, index.to_json ], "user" => tracker_file("redacted", "user") }) { site.use_instance_key!("alice-key") }
    assert connection.reload.needs_check?, "the old key's account now needs its link like everyone else"
    assert_not connection.is_key_owner?
    assert connection.profile_code
    assert connections(:alice_redacted).reload.is_key_owner?
  end

  test "only an admin connects as the key's own account" do
    sites(:redacted).update!(key_owner: :instance, instance_credential: "admin-key")
    assert_raises(Engines::Error) { Connection.connect_key_owner!(user: users(:bob), site: sites(:redacted)) }
  end

  test "the instance key isn't saved when the tracker refuses it, and members keep their keys" do
    stub_tracker({ "index" => [ 401, "" ] }) do
      assert_raises(Engines::AccessDenied) { sites(:redacted).use_instance_key!("wrong-key") }
    end
    assert sites(:redacted).reload.member_key?
    assert_equal "alice-secret-key", connections(:alice_redacted).reload.credential
  end

  test "a profile poll keeps what the profile shows, nil for what it hides, and stops when the link is gone" do
    connection = profile_connection
    profile = { "seeding" => nil, "snatched" => nil }
    stub_tracker({ "user" => profile_response(connection, community: profile) }) { assert connection.poll! }

    snapshot = connection.latest_snapshot
    assert_equal 585564424629, snapshot.uploaded
    assert_nil snapshot.seeding, "hidden by paranoia, not zero"
    assert_nil snapshot.bonus_points, "never on a profile"
    assert_equal 863, snapshot.forum_posts

    stub_tracker({ "user" => profile_response(connection, text: "no link here") }) { assert_not connection.poll! }
    assert connection.reload.needs_check?
    assert_match "isn't on your Redacted profile", connection.error_message
    assert_not Connection.pollable.exists?(connection.id)
  end

  test "a profile that hides uploaded or downloaded stops tracking, so nothing is charted as zero" do
    connection = profile_connection
    assert_no_difference -> { connection.snapshots.count } do
      stub_tracker({ "user" => profile_response(connection, stats: { "downloaded" => nil }) }) { assert_not connection.poll! }
    end
    assert connection.reload.needs_check?
  end

  test "a refused instance key pauses the site without touching members' connections" do
    connection = profile_connection
    stub_tracker({ "user" => [ 401, "" ] }) do
      assert_raises(Engines::Paused) { connection.poll! }
    end
    assert connection.reload.ok?
    assert_equal 0, connection.failure_count
    assert sites(:redacted).reload.paused_for_key_refused?
    assert_not Connection.pollable.exists?(connection.id)
  end

  test "turning a site off deletes the keys members saved for it" do
    sites(:redacted).update_availability!("off")
    connection = connections(:alice_redacted).reload
    assert_nil connection.credential
    assert connection.needs_key?
    assert connection.snapshots.exists?
  end

  private
    def profile_connection
      site = sites(:redacted)
      Connection.where(site:).update_all(credential: nil)
      site.update!(key_owner: :instance, instance_credential: "admin-key")
      connections(:alice_redacted).tap { _1.update!(profile_code: "abc123xyz0") }
    end

    def profile_response(connection, text: nil, stats: {}, community: {})
      body = JSON.parse(file_fixture("redacted/user.json").read)
      body["response"]["profileText"] = text || "[url=https://#{Rails.configuration.x.app_host}/opt-in/#{connection.profile_code}]Stats tracked with Sherlock[/url]"
      body["response"]["stats"].merge!(stats)
      body["response"]["community"].merge!(community)
      [ 200, body.to_json ]
    end
end
