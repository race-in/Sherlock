require "test_helper"

# animebytes/personal.json follows the /api/stats/personal shape other dashboards document; nobody
# here has an account to save a real answer from.
class Engines::AnimebytesTest < ActiveSupport::TestCase
  CREDENTIAL = { username: "irene", api_key: "abkey123" }.to_json

  test "stats come from /api/stats/personal with the key as a Bearer token, using credited amounts" do
    stub_tracker({ "/api/stats/personal" => tracker_file("animebytes", "personal") }) do |requests|
      stats = sites(:animebytes).adapter.fetch(CREDENTIAL)

      assert_equal "irene", stats.external_user_id
      assert_equal "irene", stats.external_username
      assert_equal 2_199_023_255_552, stats.uploaded, "account, not raw"
      assert_equal 549_755_813_888, stats.downloaded, "account, not raw"
      assert_equal BigDecimal("4"), stats.ratio
      assert_equal BigDecimal("482113"), stats.bonus_points
      assert_equal 301, stats.seeding
      assert_equal 2, stats.leeching
      assert_equal 420, stats.snatched
      assert_equal 0, stats.hit_and_runs, "active, not potential"
      assert_equal 12, stats.uploads
      assert_equal "Power User", stats.user_class

      assert_equal "https://animebytes.tv/api/stats/personal", requests.first[:uri].to_s
      assert_equal "Bearer abkey123", requests.first[:headers]["Authorization"]
    end
  end

  test "a refused key asks for a new one, other failures don't, and neither echoes the key" do
    stub_tracker({ "/api/stats/personal" => [ 403, { success: false, error: "Incorrect token" }.to_json ] }) do
      assert_raises(Engines::AccessDenied) { sites(:animebytes).adapter.fetch(CREDENTIAL) }
    end
    stub_tracker({ "/api/stats/personal" => [ 200, { success: false, error: "Down for abkey123" }.to_json ] }) do
      error = assert_raises(Engines::Error) { sites(:animebytes).adapter.fetch(CREDENTIAL) }
      assert_not_kind_of Engines::AccessDenied, error
      assert_equal "AnimeBytes said: Down for [key]", error.message
    end
  end
end
