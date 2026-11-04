require "test_helper"

# Every tracker route, as bob, against alice's connection. None may reveal or change it.
class AuthorizationTest < ActionDispatch::IntegrationTest
  setup do
    @alice = connections(:alice_redacted)
    sign_in_as users(:bob)
  end

  test "another user's tracker pages are not found" do
    [ connection_path(@alice), connection_history_path(@alice), connection_history_path(@alice, format: :csv),
      settings_connection_path(@alice), edit_settings_connection_key_path(@alice) ].each do |path|
      get path
      assert_response :not_found, path
    end
  end

  test "another user's tracker can't be changed" do
    stub_redacted_success do
      patch settings_connection_key_path(@alice), params: { connection: { api_key: "stolen" } }
      assert_response :not_found
      patch settings_connection_color_path(@alice), params: { connection: { color: "#123456" } }
      assert_response :not_found
      post settings_connection_poll_path(@alice)
      assert_response :not_found
    end
    post settings_connection_pause_path(@alice)
    assert_response :not_found
    delete settings_connection_path(@alice)
    assert_response :not_found

    @alice.reload
    assert @alice.ok?
    assert_equal "alice-secret-key", @alice.credential
  end

  test "refresh only polls your own trackers" do
    assert_enqueued_with(job: PollConnectionJob, args: [ connections(:bob_redacted) ]) do
      assert_enqueued_jobs(1, only: PollConnectionJob) { post refresh_path }
    end
    assert_redirected_to dashboard_path
  end

  test "compare ignores other users' connection ids" do
    get comparison_path(ids: [ @alice.id ])
    assert_response :success
    assert_not_includes response.body, "alice_red"
  end

  test "another user's pinned charts stay theirs" do
    get comparison_path
    assert_select "h2", text: "Pinned", count: 0

    delete comparison_pin_path(pinned_comparisons(:alice_uploaded))
    assert_response :not_found
    assert PinnedComparison.exists?(pinned_comparisons(:alice_uploaded).id)

    post comparison_pins_path, params: { stat: "buffer", range: "week", ids: [ @alice.id ] }
    assert_empty users(:bob).pinned_comparisons
  end

  test "another user's invites can't be revoked" do
    delete settings_invite_path(invites(:alice_unused))
    assert_response :not_found
    assert invites(:alice_unused).reload.usable?
  end

  test "admin pages and jobs are hidden from non-admins" do
    [ admin_users_path, admin_user_path(users(:alice)), admin_invites_path, admin_sites_path, admin_settings_path, "/jobs" ].each do |path|
      get path
      assert_response :not_found, path
    end
    post admin_user_password_reset_path(users(:alice))
    assert_response :not_found
  end

  test "signed out visitors are sent to sign in" do
    delete session_path
    [ dashboard_path, connection_path(@alice), settings_connections_path ].each do |path|
      get path
      assert_redirected_to new_session_path
    end
  end
end
