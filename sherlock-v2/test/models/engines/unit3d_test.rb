require "test_helper"

# unit3d/user.json follows UNIT3D's UserResource; nobody here has an account on a UNIT3D site to save
# a real answer from.
class Engines::Unit3dTest < ActiveSupport::TestCase
  test "stats come from /api/user with the key as a Bearer token, and display sizes become bytes" do
    stub_tracker({ "/api/user" => tracker_file("unit3d", "user") }) do |requests|
      stats = sites(:aither).adapter.fetch("u3dkey123")

      assert_equal "moriarty", stats.external_user_id
      assert_equal "moriarty", stats.external_username
      assert_equal 1_352_399_302_164, stats.uploaded, "1.23 × 1024⁴ = 1352399302164.48"
      assert_equal 550_292_684_800, stats.downloaded, "512.5 × 1024³"
      assert_equal BigDecimal("2.46"), stats.ratio
      assert_equal BigDecimal("48213.57"), stats.bonus_points
      assert_equal 142, stats.seeding
      assert_equal 1, stats.leeching
      assert_equal 2, stats.hit_and_runs
      assert_equal "Power User", stats.user_class
      assert_nil stats.snatched, "UNIT3D doesn't report it"

      assert_equal "https://aither.cc/api/user", requests.first[:uri].to_s
      assert_equal "Bearer u3dkey123", requests.first[:headers]["Authorization"]
    end
  end

  test "whole bytes, a data wrapper, an infinite ratio and missing counts are read as such" do
    body = { data: { username: "moriarty", group: "User", uploaded: 1_000_000_007, downloaded: "0 B", ratio: "∞", seedbonus: 0 } }
    stub_tracker({ "/api/user" => [ 200, body.to_json ] }) do
      stats = sites(:aither).adapter.fetch("u3dkey123")

      assert_equal 1_000_000_007, stats.uploaded
      assert_equal 0, stats.downloaded
      assert_nil stats.ratio, "∞ isn't a number to store"
      assert_equal BigDecimal("0"), stats.bonus_points
      assert_nil stats.seeding
      assert_nil stats.hit_and_runs
    end
  end

  test "a refused key or banned account asks for a new key, other failures don't, and none echo the key" do
    stub_tracker({ "/api/user" => [ 401, { message: "Unauthenticated." }.to_json ] }) do
      assert_raises(Engines::AccessDenied) { sites(:aither).adapter.fetch("u3dkey123") }
    end
    stub_tracker({ "/api/user" => [ 200, { message: "Your account is banned, u3dkey123" }.to_json ] }) do
      error = assert_raises(Engines::AccessDenied) { sites(:aither).adapter.fetch("u3dkey123") }
      assert_equal "Aither said: Your account is banned, [key]", error.message
    end
    stub_tracker({ "/api/user" => [ 200, { username: "moriarty", uploaded: "1.2 EiB", downloaded: "0 B" }.to_json ] }) do
      error = assert_raises(Engines::Error) { sites(:aither).adapter.fetch("u3dkey123") }
      assert_not_kind_of Engines::AccessDenied, error
      assert_equal "Aither sent a response Sherlock doesn't understand.", error.message
    end
    stub_tracker({ "/api/user" => [ 200, "<html>Just a moment...</html>" ] }) do
      assert_raises(Engines::Error) { sites(:aither).adapter.fetch("u3dkey123") }
    end
  end
end
