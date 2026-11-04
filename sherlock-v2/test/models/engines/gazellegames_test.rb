require "test_helper"

class Engines::GazellegamesTest < ActiveSupport::TestCase
  test "stats come from quick_user with the key in X-API-Key" do
    stub_tracker({ "quick_user" => tracker_file("gazellegames", "quick_user") }) do |requests|
      stats = sites(:gazellegames).adapter.fetch("ggnkey123")

      assert_equal "24", stats.external_user_id
      assert_equal "xFyrios", stats.external_username
      assert_equal 585_564_424_629, stats.uploaded
      assert_equal 177_461_229_738, stats.downloaded
      assert_equal BigDecimal("3.29"), stats.ratio
      assert_equal BigDecimal("0.6"), stats.required_ratio
      assert_equal "VIP", stats.user_class
      assert_nil stats.bonus_points, "quick_user doesn't report it"

      assert_equal "https://gazellegames.net/api.php?request=quick_user", requests.first[:uri].to_s
      assert_equal "ggnkey123", requests.first[:headers]["X-API-Key"]
      assert_nil requests.first[:headers]["Authorization"]
    end
  end

  test "a refused key asks for a new one, other failures don't, and neither echoes the key" do
    stub_tracker({ "quick_user" => [ 401, { status: "failure", error: "APIKey is not valid." }.to_json ] }) do
      assert_raises(Engines::AccessDenied) { sites(:gazellegames).adapter.fetch("ggnkey123") }
    end
    stub_tracker({ "quick_user" => [ 200, { status: "failure", error: "Something broke for ggnkey123" }.to_json ] }) do
      error = assert_raises(Engines::Error) { sites(:gazellegames).adapter.fetch("ggnkey123") }
      assert_not_kind_of Engines::AccessDenied, error
      assert_equal "GazelleGames said: Something broke for [key]", error.message
    end
  end

  test "with the instance key, a member's profile is read once their opt-in link is on it, and paranoia leaves gaps" do
    site = sites(:gazellegames)
    site.update!(key_owner: :instance, instance_credential: "adminkey")
    body = JSON.parse(file_fixture("gazellegames/user.json").read)
    # GGn may only fill the BBCode text; hidden stats are simply left out.
    body["response"]["bbProfileText"] = "[url=https://#{Rails.configuration.x.app_host}/opt-in/abcde12345]Stats tracked with Sherlock[/url]"
    body["response"]["community"].delete("seeding")
    body["response"]["stats"].delete("ratio")

    stub_tracker({ "user" => [ 200, body.to_json ] }) do |requests|
      stats = site.adapter.fetch_profile("24", "abcde12345")

      assert_equal "xFyrios", stats.external_username
      assert_equal 585_564_424_629, stats.uploaded
      assert_equal 177_461_229_738, stats.downloaded
      assert_nil stats.ratio, "hidden by paranoia, not zero"
      assert_nil stats.seeding, "hidden by paranoia, not zero"
      assert_equal 678, stats.snatched
      assert_equal 1, stats.hit_and_runs
      assert_equal "https://gazellegames.net/api.php?request=user&id=24", requests.first[:uri].to_s
      assert_equal "adminkey", requests.first[:headers]["X-API-Key"]
    end

    stub_tracker({ "user" => [ 200, body.to_json ] }) do
      error = assert_raises(Engines::CheckNeeded) { site.adapter.fetch_profile("24", "zzzzz99999") }
      assert_match "isn't on your GazelleGames profile", error.message
    end
    stub_tracker({ "user" => [ 200, { status: "failure", error: "User not found" }.to_json ] }) do
      assert_raises(Engines::CheckNeeded) { site.adapter.fetch_profile("999", "abcde12345") }
    end
    stub_tracker({ "user" => [ 401, { status: "failure", error: "APIKey is not valid." }.to_json ] }) do
      assert_raises(Engines::Paused) { site.adapter.fetch_profile("24", "abcde12345") }
    end
    assert site.reload.paused?, "a refused instance key pauses the whole site"
  end

  test "GazelleGames members can opt in: a profile link picks the site, and an instance key needs the user request" do
    site = sites(:gazellegames)
    assert site.opt_in_possible?
    claim = ProfileClaim.start("gazellegames.net/user.php?id=24", sites: [ sites(:redacted), site ])
    assert_equal [ site, "24" ], [ claim.site, claim.external_user_id ]

    stub_tracker({ "quick_user" => tracker_file("gazellegames", "quick_user"), "user" => tracker_file("gazellegames", "user") }) do
      assert_equal "24", site.adapter.check_instance_key("adminkey")
    end
    stub_tracker({ "quick_user" => tracker_file("gazellegames", "quick_user"), "user" => [ 200, { status: "failure", error: "Missing permission" }.to_json ] }) do
      error = assert_raises(Engines::Error) { site.adapter.check_instance_key("adminkey") }
      assert_match "needs the User permission", error.message
    end
  end
end
