require "test_helper"

class CheckForUpdateJobTest < ActiveJob::TestCase
  TAGS = "/api/v1/repos/whatstatus/sherlock-v2/tags"

  test "keeps the highest released version, comparing numbers rather than text" do
    InstanceSetting.current.update!(is_update_check_enabled: true)
    tags = [ "v1.0.9", "v1.0.10", "v1.1.0-rc1", "nightly" ].map { { "name" => _1 } }
    stub_tracker({ TAGS => [ 200, tags.to_json ] }) do |requests|
      CheckForUpdateJob.perform_now
      assert_equal "codeberg.org", requests.sole[:uri].host
    end

    setting = InstanceSetting.current
    assert_equal "v1.0.10", setting.latest_version
    assert_in_delta Time.current, setting.update_checked_at, 5
  end

  test "asks nothing while update checks are off" do
    stub_tracker({}) do |requests|
      CheckForUpdateJob.perform_now
      assert_empty requests
    end
    assert_nil InstanceSetting.current.update_checked_at
  end

  test "an error from Codeberg keeps the last answer" do
    InstanceSetting.current.update!(is_update_check_enabled: true, latest_version: "v1.0.3")
    stub_tracker({ TAGS => [ 502, "" ] }) { CheckForUpdateJob.perform_now }
    assert_equal "v1.0.3", InstanceSetting.current.latest_version
  end
end
