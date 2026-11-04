require "test_helper"

class OpenInvitesTest < ActionDispatch::IntegrationTest
  setup do
    @site = sites(:redacted)
    Connection.where(site: @site).update_all(credential: nil)
    @site.update!(key_owner: :instance, instance_credential: "admin-key")
    @invite = users(:admin).created_invites.create!(max_uses: 100, expires_at: nil)
  end

  test "joining with an open invite: profile link, opt-in link, check, account" do
    get join_path(@invite)
    assert_select "input[name=profile_url]"

    post join_profile_path(@invite), params: { profile_url: "https://redacted.sh/user.php?id=4242" }
    follow_redirect!
    code = response.body[%r{/opt-in/([a-z0-9]{10})}, 1]
    assert code, "shows the member's opt-in link"

    stub_tracker({ "user" => profile(code, text: "nothing yet") }) { post join_check_path(@invite) }
    assert_response :unprocessable_entity
    assert_select "[role=alert]", text: /isn't on your Redacted profile/
    assert_no_match "dr4g0n", response.body, "nothing read is shown before the link is found"

    stub_tracker({ "user" => profile(code) }) { post join_check_path(@invite) }
    follow_redirect!
    assert_match "dr4g0n", response.body

    post join_path(@invite), params: { user: { username: "newmember", password: "[REDACTED:password]", time_zone: "UTC" } }
    assert_redirected_to onboarding_welcome_path
    connection = User.find_by!(username: "newmember").connections.sole
    assert_equal "4242", connection.external_user_id
    assert_equal code, connection.profile_code
    assert_nil connection.credential
    assert_equal 1, @invite.reload.uses

    # They never give Sherlock a key, so onboarding asks for no key rules and skips adding trackers.
    get onboarding_welcome_path
    assert_select "input[name=accept][type=checkbox]", count: 0
    patch onboarding_welcome_path
    assert_redirected_to onboarding_preferences_path
    patch onboarding_preferences_path, params: { user: { time_zone: "UTC" } }
    assert_redirected_to onboarding_completion_path
  end

  test "an invite for one tracker shows only that tracker and turns away the others' profiles" do
    orpheus = sites(:orpheus)
    orpheus.update_columns(key_owner: "instance", instance_credential: "admin-key", availability: "everyone", privacy_settings_url: "https://orpheus.network/user.php?action=edit")
    sign_in_as users(:admin)
    post admin_invites_path, params: { invite: { uses: "unlimited", expires: "never", site_id: orpheus.id } }
    invite = Invite.order(:id).last
    assert_equal orpheus, invite.site
    delete session_path

    get join_path(invite)
    assert_select "input[name=profile_url][placeholder^='https://orpheus.network/']"
    post join_profile_path(invite), params: { profile_url: "https://redacted.sh/user.php?id=4242" }
    assert_equal "That isn't a profile link from Orpheus.", flash[:alert]
  end

  test "an account can't be created before the profile is checked" do
    post join_path(@invite), params: { user: { username: "newmember", password: "[REDACTED:password]", time_zone: "UTC" } }
    assert_response :unprocessable_entity
    assert_not User.exists?(username: "newmember")
  end

  test "the opt-in page is the same for every code and looks nothing up" do
    get opt_in_path(connections(:alice_redacted).tap { _1.update!(profile_code: "abc123xyz0") }.profile_code)
    tracked = response.body
    get opt_in_path("zzzzzzzzzz")
    assert_response :success
    per_request = /<meta name="(csrf-token|csp-nonce)"[^>]*>/
    assert_equal tracked.gsub(per_request, ""), response.body.gsub(per_request, "")
  end

  private
    def profile(code, text: nil)
      body = JSON.parse(file_fixture("redacted/user.json").read)
      body["response"]["profileText"] = text || "[url=https://#{Rails.configuration.x.app_host}/opt-in/#{code}]Stats tracked with Sherlock[/url]"
      [ 200, body.to_json ]
    end
end
