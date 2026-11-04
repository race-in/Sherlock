require "test_helper"

class AdminSetupTest < ActionDispatch::IntegrationTest
  include TrackerStub

  setup do
    @admin = users(:admin)
    @admin.connections.destroy_all
    @admin.created_invites.destroy_all
    InstanceSetting.current.update!(tracker_contact: nil)
    connections(:alice_redacted).update!(external_user_id: "999")
    Site.update_all(availability: "off")
    sign_in_as @admin
  end

  test "the admin sets up on the dashboard: contact, then the first tracker with their key for everyone, an invite and update checks" do
    get dashboard_path
    assert_select "input[name='instance_setting[tracker_contact]']"
    assert_select "turbo-frame#first_tracker", count: 0
    get tracker_selection_path
    assert_redirected_to dashboard_path, "no tracker before the contact"

    patch admin_settings_path, params: { instance_setting: { tracker_contact: "admin on IRC" } }, headers: { "Referer" => dashboard_url }
    get dashboard_path(setup_site: "redacted")
    assert_select "input[type=checkbox][name=share]"

    stub_redacted_success do
      post admin_site_setup_path("redacted"), params: { share: "1", from: "dashboard", connection: { api_key: "admin-key" } }
    end
    assert_redirected_to dashboard_path
    site = sites(:redacted).reload
    assert_equal :opt_in, site.audience
    connection = @admin.connections.reload.sole
    assert connection.is_key_owner?
    assert_nil connection.profile_code

    get dashboard_path
    assert_select "a[href='https://codeberg.org/codeberg/org/src/branch/main/PrivacyPolicy.md']", count: 0, message: "update checks come after the invites"
    assert_enqueued_with(job: CheckForUpdateJob) do
      patch admin_settings_path, params: { instance_setting: { is_update_check_enabled: "1" } }, headers: { "Referer" => dashboard_url }
    end
    assert_redirected_to dashboard_url

    post admin_invites_path, params: { invite: { uses: "unlimited", expires: "never" } }, headers: { "Referer" => dashboard_url }
    assert_redirected_to dashboard_url
    follow_redirect!
    assert_select "h2", text: "Set up your Sherlock", count: 0
    assert_select "code", text: join_url(@admin.created_invites.reload.sole.code)
    assert_select "a[href='#{admin_invites_path}']", text: /Active invites/

    Invite.usable.find_each(&:revoke!)
    get dashboard_path
    assert_select "a", text: /Active invites/, count: 0
  end

  test "a tracker only for the admin stays closed to members, and a refused key leaves it as it was" do
    InstanceSetting.current.update!(tracker_contact: "admin on IRC")
    site = sites(:orpheus)
    site.update!(availability: :off)
    get new_admin_site_setup_path(site)
    assert_select "span", text: /Only if Orpheus's rules allow it/, message: "Orpheus can't read profiles here, so sharing means members' own keys"

    stub_tracker({ "index" => [ 401, "" ] }) do
      post admin_site_setup_path(site), params: { share: "0", connection: { api_key: "wrong" } }
    end
    assert_redirected_to new_admin_site_setup_path(site, share: "0")
    assert site.reload.off?
    follow_redirect!
    assert_select "[role=alert]", text: /Orpheus returned 401/

    stub_tracker({ "index" => tracker_file("redacted", "index"), "community_stats" => tracker_file("redacted", "community_stats"),
                   "user" => tracker_file("redacted", "user") }) do
      post admin_site_setup_path(site), params: { share: "0", connection: { api_key: "admin-key" } }
    end
    assert_redirected_to admin_site_path(site)
    assert_equal :only_me, site.reload.audience
    assert_equal "admin-key", @admin.connections.reload.sole.credential
  end

  test "sharing a tracker that can't read profiles opens it to everyone with their own key, and unsharing closes it" do
    InstanceSetting.current.update!(tracker_contact: "admin on IRC")
    site = sites(:orpheus)
    stub_tracker({ "index" => tracker_file("redacted", "index"), "community_stats" => tracker_file("redacted", "community_stats"),
                   "user" => tracker_file("redacted", "user") }) do
      post admin_site_setup_path(site), params: { share: "1", connection: { api_key: "admin-key" } }
    end
    assert_equal :own_keys, site.reload.audience

    post admin_site_setup_path(site), params: { share: "0" }
    assert_equal :only_me, site.reload.audience, "the admin's account is on already, so no key is needed to change this"
  end

  test "unsharing a tracker read with the admin's key asks for the admin's own key, and keeps their account" do
    InstanceSetting.current.update!(tracker_contact: "admin on IRC")
    stub_redacted_success { post admin_site_setup_path("redacted"), params: { share: "1", connection: { api_key: "admin-key" } } }
    connection = @admin.connections.reload.sole

    post admin_site_setup_path("redacted"), params: { share: "0" }
    assert sites(:redacted).reload.instance_key?, "no key given, so nothing changed"
    stub_redacted_success { post admin_site_setup_path("redacted"), params: { share: "0", connection: { api_key: "own-key" } } }
    assert_equal :only_me, sites(:redacted).reload.audience
    assert_equal "own-key", connection.reload.credential
    assert connection.ok?
  end

  test "the unshare warning only shows when changing a shared tracker that others track" do
    get new_admin_site_setup_path("redacted")
    assert_select "span", text: /Saving stops updates/, count: 0, message: "a first setup: the tracker is off"

    sites(:redacted).update!(availability: "everyone")
    get new_admin_site_setup_path("redacted")
    assert_select "span", text: "Saving stops updates for 2 members."
  end

  test "no tracker before the contact" do
    post admin_site_setup_path("redacted"), params: { share: "1", connection: { api_key: "admin-key" } }
    assert_redirected_to dashboard_path
    assert sites(:redacted).reload.member_key?
  end

  test "the invite form says which trackers people who join can track, and warns when there are none" do
    Site.update_all(availability: "off")
    sites(:redacted).update!(availability: "everyone")
    sites(:orpheus).update!(availability: "granted")
    get admin_invites_path
    assert_select "p", text: /People who join can track their stats on Redacted\. Orpheus only for you and people you grant it to\./

    sites(:redacted).update!(availability: "off")
    get admin_invites_path
    assert_select "[role=alert]", text: /People who join can't track any tracker yet/
  end

  test "only the invite and update steps can be skipped" do
    post admin_setup_skips_path, params: { step: "first_tracker" }
    assert_response :unprocessable_entity
    post admin_setup_skips_path, params: { step: "invites" }
    post admin_setup_skips_path, params: { step: "updates" }
    assert_equal [ "invites", "updates" ], InstanceSetting.current.skipped_setup_steps
  end

  test "update checks start off, and turning them off later doesn't bring the setup back" do
    InstanceSetting.current.update!(tracker_contact: "admin on IRC")
    sites(:redacted).update!(availability: "everyone")
    post admin_setup_skips_path, params: { step: "invites" }
    get dashboard_path
    assert_select "button", text: /Turn on update checks/
    assert_select "a[href='https://codeberg.org/codeberg/org/src/branch/main/PrivacyPolicy.md']"
    assert_not InstanceSetting.current.is_update_check_enabled?

    patch admin_settings_path, params: { instance_setting: { is_update_check_enabled: "1" } }
    get dashboard_path
    assert_select "h2", text: "Set up your Sherlock", count: 0

    assert_no_enqueued_jobs(only: CheckForUpdateJob) do
      patch admin_settings_path, params: { instance_setting: { is_update_check_enabled: "0" } }
    end
    assert_equal "Update checks off.", flash[:notice]
    get dashboard_path
    assert_select "h2", text: "Set up your Sherlock", count: 0
  end

  test "members never see the setup" do
    sign_in_as users(:alice)
    get dashboard_path
    assert_select "h2", text: "Set up your Sherlock", count: 0
    post admin_setup_skips_path, params: { step: "invites" }
    assert_response :not_found
    post admin_site_setup_path("redacted"), params: { share: "1", connection: { api_key: "k" } }
    assert_response :not_found
  end
end
