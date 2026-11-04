require "test_helper"

class Engines::GazelleTest < ActiveSupport::TestCase
  test "redacted stats come from index, community_stats and user with the bare key" do
    stub_redacted_success do |requests|
      stats = sites(:redacted).adapter.fetch("abc123")

      assert_equal "469", stats.external_user_id
      assert_equal "dr4g0n", stats.external_username
      assert_equal 585_564_424_629, stats.uploaded
      assert_equal 177_461_229_738, stats.downloaded
      assert_equal BigDecimal("3.29"), stats.ratio
      assert_equal BigDecimal("0.6"), stats.required_ratio
      assert_equal 1413, stats.seeding
      assert_equal 0, stats.leeching
      assert_equal 1574, stats.snatched
      assert_equal 29, stats.uploads
      assert_equal 863, stats.forum_posts
      assert_equal 13, stats.torrent_comments
      assert_equal "VIP", stats.user_class
      assert_nil stats.bonus_points, "Redacted doesn't report bonus points"

      assert_equal [ "abc123" ] * 3, requests.map { _1[:headers]["Authorization"] }
      assert_equal [ "action=community_stats&userid=469", "action=user&id=469" ], requests.drop(1).map { _1[:uri].query }
    end
  end

  test "orpheus sends token prefix, reads bonus points and takes torrent counts from user" do
    stub_tracker({ "index" => tracker_file("orpheus", "index"), "community_stats" => tracker_file("orpheus", "community_stats"), "user" => tracker_file("orpheus", "user") }) do |requests|
      stats = sites(:orpheus).adapter.fetch("abc123")

      assert_equal BigDecimal("220903"), stats.bonus_points
      assert_equal 1413, stats.seeding
      assert_equal 0, stats.leeching
      assert_equal 1574, stats.snatched
      assert_equal "token abc123", requests.first[:headers]["Authorization"]
      assert_equal "orpheus.network", requests.first[:uri].host
    end
  end

  test "a key without the User scope still polls, and the counts only user returns stay nil" do
    # Redacted doesn't document the refusal, so cover both a failure body and a 403.
    [ [ 200, { status: "failure", error: "no access" }.to_json ], [ 403, "" ] ].each do |refusal|
      stub_tracker({ "index" => tracker_file("redacted", "index"), "community_stats" => tracker_file("redacted", "community_stats"), "user" => refusal }) do
        stats = sites(:redacted).adapter.fetch("abc123")

        assert_equal 1413, stats.seeding
        assert_nil stats.uploads
        assert_nil stats.forum_posts
        assert_nil stats.torrent_comments
      end
    end
  end

  test "rate limiting on the user call still stops the poll" do
    stub_tracker({ "index" => tracker_file("redacted", "index"), "community_stats" => tracker_file("redacted", "community_stats"), "user" => [ 429, "", { "Retry-After" => "5" } ] }) do
      assert_raises(Engines::RateLimited) { sites(:redacted).adapter.fetch("abc123") }
    end
  end

  test "invalid token is access denied and never echoes the key" do
    stub_tracker({ "index" => [ 200, { status: "failure", error: "invalid token" }.to_json ] }) do
      error = assert_raises(Engines::AccessDenied) { sites(:redacted).adapter.fetch("abc123") }
      assert_equal "Redacted said: invalid token", error.message
    end
  end

  test "other failure text is a plain error, capped and scrubbed of the key" do
    stub_tracker({ "index" => [ 200, { status: "failure", error: "bad key abc123 " + "x" * 500 }.to_json ] }) do
      error = assert_raises(Engines::Error) { sites(:redacted).adapter.fetch("abc123") }
      assert_not_kind_of Engines::AccessDenied, error
      assert_not_includes error.message, "abc123"
      assert_operator error.message.length, :<=, 220
    end
  end

  test "401 and 403 are access denied" do
    [ 401, 403 ].each do |code|
      stub_tracker({ "index" => [ code, "nope" ] }) do
        assert_raises(Engines::AccessDenied) { sites(:redacted).adapter.fetch("abc123") }
      end
    end
  end

  test "html or missing fields are an error, not a crash" do
    stub_tracker({ "index" => [ 200, "<html>maintenance</html>" ] }) do
      assert_raises(Engines::Error) { sites(:redacted).adapter.fetch("abc123") }
    end
    stub_tracker({ "index" => [ 200, { status: "success", response: { id: 1 } }.to_json ] }) do
      assert_raises(Engines::Error) { sites(:redacted).adapter.fetch("abc123") }
    end
  end
end
