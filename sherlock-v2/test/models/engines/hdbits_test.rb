require "test_helper"

class Engines::HdbitsTest < ActiveSupport::TestCase
  CREDENTIAL = { username: "valerio", passkey: "s3cretpasskey" }.to_json

  test "stats come from /api/user with the username and passkey in the body" do
    stub_tracker_post(tracker_file("hdbits", "user")) do |requests|
      stats = sites(:hdbits).adapter.fetch(CREDENTIAL)

      assert_equal "1003051", stats.external_user_id
      assert_equal "valerio", stats.external_username
      assert_equal 34_463_038_426_408, stats.uploaded
      assert_equal 17_231_519_213_204, stats.downloaded
      assert_equal BigDecimal("2.0"), stats.ratio, "34463038426408 / 17231519213204 is exactly 2"
      assert_equal BigDecimal("578684"), stats.bonus_points
      assert_nil stats.seeding, "HDBits doesn't report it"

      assert_equal "https://hdbits.org/api/user", requests.first[:uri].to_s
      assert_equal({ username: "valerio", passkey: "s3cretpasskey" }, requests.first[:body])
    end
  end

  test "a refused login asks for a new key and never echoes the passkey" do
    stub_tracker_post([ 200, { status: 5, message: "Invalid authentication credentials for s3cretpasskey" }.to_json ]) do
      error = assert_raises(Engines::AccessDenied) { sites(:hdbits).adapter.fetch(CREDENTIAL) }
      assert_equal "HDBits said: Invalid authentication credentials for [key]", error.message
    end
  end

  test "other API failures are passing errors" do
    stub_tracker_post([ 200, { status: 1, message: "Failure" }.to_json ]) do
      error = assert_raises(Engines::Error) { sites(:hdbits).adapter.fetch(CREDENTIAL) }
      assert_not_kind_of Engines::AccessDenied, error
    end
  end
end
