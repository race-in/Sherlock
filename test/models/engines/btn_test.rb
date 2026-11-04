require "test_helper"

class Engines::BtnTest < ActiveSupport::TestCase
  test "stats come from userInfo, with every number sent as a string" do
    stub_tracker_post(tracker_file("broadcasthenet", "userInfo")) do |requests|
      stats = sites(:broadcasthenet).adapter.fetch("btnkey123")

      assert_equal "48151", stats.external_user_id
      assert_equal "hurley", stats.external_username
      assert_equal 5_497_558_138_880, stats.uploaded
      assert_equal 2_199_023_255_552, stats.downloaded
      assert_equal BigDecimal("2.5"), stats.ratio, "5 TiB / 2 TiB"
      assert_equal BigDecimal("84213"), stats.bonus_points, "Bonus, not Lumens"
      assert_equal 612, stats.snatched
      assert_equal 1, stats.hit_and_runs
      assert_equal "Elite", stats.user_class
      assert_nil stats.seeding

      assert_equal({ id: 1, method: "userInfo", params: { key: "btnkey123" } }, requests.first[:body])
    end
  end

  test "error codes map to a bad key, a rate limit, or a passing error like an unapproved IP" do
    { -32001 => Engines::AccessDenied, -32003 => Engines::AccessDenied, -32002 => Engines::RateLimited, -32004 => Engines::Error }.each do |code, error_class|
      stub_tracker_post([ 200, { id: 1, result: nil, error: { code:, message: "IP address needs authorization (btnkey123)" } }.to_json ]) do
        error = assert_raises(Engines::Error) { sites(:broadcasthenet).adapter.fetch("btnkey123") }
        assert_instance_of error_class, error, code
        assert_not_includes error.message, "btnkey123"
      end
    end
  end
end
