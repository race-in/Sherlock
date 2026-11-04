require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:bob) }

  test "the dashboard shows a refresh as running until every tracker has answered" do
    post refresh_path
    get dashboard_path
    assert_select "form[action='#{refresh_path}'] button[aria-busy=true][disabled]"
    assert_select ".is-refreshing"

    connections(:bob_redacted).update!(polled_at: Time.current)
    get dashboard_path
    assert_select "form[action='#{refresh_path}'] button[aria-busy=true]", 0
    assert_select ".is-refreshing", 0
  end

  test "admins see a newer version until they close it for that version, members never do" do
    running = Rails.configuration.x.version
    Rails.configuration.x.version = "v1.0.9"
    InstanceSetting.current.update!(is_update_check_enabled: true, latest_version: "v1.0.10")
    get dashboard_path
    assert_select "p", text: "Sherlock v1.0.10 is out", count: 0, message: "bob isn't an admin"

    sign_in_as users(:admin)
    get dashboard_path
    assert_select "p", text: "Sherlock v1.0.10 is out"

    post dismissals_path, params: { notice: "update" }
    get dashboard_path
    assert_select "p", text: "Sherlock v1.0.10 is out", count: 0

    InstanceSetting.current.update!(latest_version: "v1.1.0")
    get dashboard_path
    assert_select "p", text: "Sherlock v1.1.0 is out", message: "closing lasts until the next version"

    InstanceSetting.current.update!(is_update_check_enabled: false)
    get dashboard_path
    assert_select "p", text: "Sherlock v1.1.0 is out", count: 0, message: "nothing while checks are off"

    InstanceSetting.current.update!(is_update_check_enabled: true, latest_version: "v1.0.9")
    get dashboard_path
    assert_select "p", text: /is out/, count: 0, message: "nothing when it runs the newest version"
  ensure
    Rails.configuration.x.version = running
  end

  test "a refresh stops showing as running after two minutes" do
    post refresh_path
    travel 3.minutes
    get dashboard_path
    assert_select "form[action='#{refresh_path}'] button[aria-busy=true]", 0
  end

  test "a new tracker says the charts fill in, a paused one says why nothing updates, and nobody is left without a next step" do
    sign_in_as users(:alice)
    get dashboard_path
    assert_select "p", text: "Your first numbers are in", count: 0, message: "alice has tracked for 3 days"

    connections(:alice_redacted).snapshots.update_all(created_at: 2.hours.ago)
    sites(:redacted).pause!(:admin)
    get dashboard_path
    assert_select "p", text: "Your first numbers are in"
    assert_select "p", text: "Redacted is paused on this Sherlock"

    post dismissals_path, params: { notice: "first_numbers" }
    get dashboard_path
    assert_select "p", text: "Your first numbers are in", count: 0, message: "dismissed for good"
    post dismissals_path, params: { notice: "anything_else" }
    assert_response :unprocessable_entity

    user = User.create!(username: "newcomer", password: "correct-horse-battery", time_zone: "UTC", invited_by_user: users(:alice),
      tracker_rules_accepted_at: Time.current, onboarding_completed_at: Time.current)
    sign_in_as user
    Site.update_all(availability: "off")
    get dashboard_path
    assert_select "p", text: "No trackers are open to you yet"
    assert_select "a.btn-primary[href='#{tracker_selection_path}']", count: 0
    get tracker_selection_path
    assert_select "p", text: /No trackers are open to you/
  end
end
