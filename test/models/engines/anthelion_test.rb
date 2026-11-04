require "test_helper"

# anthelion/user.json follows the getuserinfo field names other dashboards document; nobody here has
# an account to save a real answer from.
class Engines::AnthelionTest < ActiveSupport::TestCase
  CREDENTIAL = { username: "irene adler", api_key: "antkey123" }.to_json

  test "stats come from getuserinfo by username, with numbers sent as text or numbers" do
    stub_tracker({ "user" => tracker_file("anthelion", "user") }) do |requests|
      stats = sites(:anthelion).adapter.fetch(CREDENTIAL)

      assert_equal "31337", stats.external_user_id
      assert_equal "irene", stats.external_username
      assert_equal 2_748_779_069_440, stats.uploaded
      assert_equal 1_099_511_627_776, stats.downloaded
      assert_equal BigDecimal("2.5"), stats.ratio, "2.5 TiB / 1 TiB"
      assert_equal BigDecimal("152340"), stats.bonus_points
      assert_equal 412, stats.seeding
      assert_equal 488, stats.snatched
      assert_equal 0, stats.hit_and_runs
      assert_equal 17, stats.uploads
      assert_equal 63, stats.forum_posts
      assert_equal "Power User", stats.user_class
      assert_nil stats.leeching, "Anthelion doesn't report it"

      query = URI.decode_www_form(requests.first[:uri].query).to_h
      assert_equal "https://anthelion.me/api.php", requests.first[:uri].to_s.split("?").first
      assert_equal({ "action" => "user", "method" => "getuserinfo", "type" => "username", "user" => "irene adler", "api_key" => "antkey123" }, query)
    end
  end

  test "a refused key asks for a new one, other failures don't, and neither echoes the key" do
    stub_tracker({ "user" => [ 403, { status: "failure", error: "Unrecognized key" }.to_json ] }) do
      error = assert_raises(Engines::AccessDenied) { sites(:anthelion).adapter.fetch(CREDENTIAL) }
      assert_equal "Anthelion said: Unrecognized key", error.message
    end
    stub_tracker({ "user" => [ 200, { status: "failure", error: "No such user for antkey123" }.to_json ] }) do
      error = assert_raises(Engines::Error) { sites(:anthelion).adapter.fetch(CREDENTIAL) }
      assert_not_kind_of Engines::AccessDenied, error
      assert_equal "Anthelion said: No such user for [key]", error.message
    end
  end
end
