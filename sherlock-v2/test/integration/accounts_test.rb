require "test_helper"

class AccountsTest < ActionDispatch::IntegrationTest
  test "sign in with username and password" do
    sign_in_as users(:alice)
    assert_redirected_to dashboard_url
    follow_redirect!
    assert_response :success
    assert_equal %w[created_at id updated_at user_id], Session.column_names.sort,
      "the privacy page promises no IP address or browser"
  end

  test "the privacy policy is public" do
    get privacy_path
    assert_response :success
    assert_select "a[href='https://codeberg.org/whatstatus/sherlock-v2']"
    assert_match(/script-src 'self' 'nonce-[^']+'; style-src/, response.headers["Content-Security-Policy"])
  end

  test "signing out forgets everything the browser session held" do
    sign_in_as users(:alice)
    post refresh_path
    assert session[:refresh_requested_at]
    delete session_path
    assert_nil session[:refresh_requested_at]
  end

  # The set_updated_at() trigger stamps the database's own time, which in a test is when its transaction
  # began. So the test moves Ruby's clock, and only checks that a touch changed the stamp.
  test "a session moves while it's used and ends after 90 idle days" do
    sign_in_as users(:alice)
    session = users(:alice).sessions.sole
    signed_in_at = session.updated_at

    travel 30.minutes do
      get dashboard_path
      assert_equal signed_in_at, session.reload.updated_at
    end
    travel 2.hours do
      get dashboard_path
      assert_not_equal signed_in_at, session.reload.updated_at
    end
    travel 91.days do
      get dashboard_path
      assert_redirected_to new_session_path
      assert_equal [ session ], Session.expired.to_a
    end
  end

  test "wrong password and disabled users can't sign in" do
    post session_path, params: { username: "alice", password: "wrong" }
    assert_redirected_to new_session_path

    users(:alice).disable!
    sign_in_as users(:alice)
    assert_redirected_to new_session_path
  end

  test "disabling a user ends their current session" do
    sign_in_as users(:bob)
    users(:bob).disable!
    get dashboard_path
    assert_redirected_to new_session_path
  end

  test "a fresh install asks for the first account, makes it the admin, then closes" do
    User.delete_all
    get root_path
    assert_redirected_to first_run_path
    get new_session_path
    assert_redirected_to first_run_path

    post first_run_path, params: { user: { username: "Holmes", password: "first-admin-password", time_zone: "Europe/London" } }
    assert_redirected_to onboarding_welcome_path
    holmes = User.find_by!(username: "holmes")
    assert holmes.is_admin?
    assert_nil holmes.invited_by_user

    delete session_path
    get first_run_path
    assert_redirected_to root_path
    post first_run_path, params: { user: { username: "moriarty", password: "second-admin-password", time_zone: "UTC" } }
    assert_redirected_to root_path
    assert_not User.exists?(username: "moriarty")
  end

  test "joining with an invite creates the account and starts onboarding" do
    get join_path(invites(:alice_unused).code)
    assert_response :success
    assert_includes response.body, "alice"

    post join_path(invites(:alice_unused).code), params: { user: { username: "carol", password: "long-enough-pw", time_zone: "Europe/Berlin" } }
    assert_redirected_to onboarding_welcome_path
    assert_equal users(:alice), User.find_by!(username: "carol").invited_by_user

    get dashboard_path
    assert_redirected_to onboarding_welcome_path
  end

  test "used or unknown invite codes are turned away" do
    get join_path("nope")
    assert_redirected_to new_join_path
    get join_path(invites(:admin_used).code)
    assert_redirected_to new_join_path
  end

  test "after an operator reset the user must set a new password first" do
    temporary = users(:bob).reset_password!
    post session_path, params: { username: "bob", password: temporary }
    get dashboard_path
    assert_redirected_to edit_password_path

    patch password_path, params: { user: { password_challenge: temporary, password: "brand-new-password", password_confirmation: "brand-new-password" } }
    get dashboard_path
    assert_response :success
  end

  test "changing the password needs the current one, even when it's sent as null" do
    sign_in_as users(:alice)
    digest = users(:alice).password_digest
    patch password_path, params: { user: { password_challenge: nil, password: "attacker-password", password_confirmation: "attacker-password" } }.to_json,
      headers: { "Content-Type" => "application/json" }
    assert_response :unprocessable_entity
    assert_equal digest, users(:alice).reload.password_digest
  end

  test "connecting a tracker never shows the key again" do
    sign_in_as users(:bob)
    stub_redacted_success do
      post site_connection_path(site_slug: "orpheus"), params: { connection: { api_key: "very-secret-key-123" } }
    end
    connection = users(:bob).connections.find_by!(site: sites(:orpheus))
    [ connection_path(connection), settings_connection_path(connection), edit_settings_connection_key_path(connection), settings_data_path ].each do |path|
      get path
      assert_not_includes response.body, "very-secret-key-123", path
    end
  end

  test "hdbits is only offered to people an admin granted it, and takes a username and passkey" do
    sign_in_as users(:bob)
    get tracker_selection_path
    assert_select "#site_orpheus"
    assert_select "#site_hdbits", count: 0
    get new_site_connection_path(site_slug: "hdbits")
    assert_response :not_found
    patch tracker_selection_path, params: { slugs: [ "hdbits" ] }
    assert_not_includes response.location, "hdbits"
    assert_raises(Engines::Error) { Connection.connect!(user: users(:bob), site: sites(:hdbits), api_key: "x") }

    # A grant from a non-admin goes nowhere.
    post admin_user_grants_path(users(:bob)), params: { slug: "hdbits" }
    assert_response :not_found
    delete session_path
    sign_in_as users(:admin)
    post admin_user_grants_path(users(:bob)), params: { slug: "orpheus" }
    assert_response :not_found, "only granted trackers take grants"
    post admin_user_grants_path(users(:bob)), params: { slug: "hdbits" }
    assert_redirected_to admin_user_path(users(:bob))
    delete session_path
    sign_in_as users(:bob)

    get tracker_selection_path
    assert_select "#site_hdbits"
    assert_includes response.body, sites(:hdbits).credential_warning
    stub_tracker_post(tracker_file("hdbits", "user")) do
      post site_connection_path(site_slug: "hdbits"), params: { connection: { username: " valerio ", api_key: "hdbits-passkey-456" } }
    end
    connection = users(:bob).connections.find_by!(site: sites(:hdbits))
    assert_equal({ "username" => "valerio", "passkey" => "hdbits-passkey-456" }, JSON.parse(connection.credential))
    [ connection_path(connection), settings_connection_path(connection), edit_settings_connection_key_path(connection) ].each do |path|
      get path
      assert_not_includes response.body, "hdbits-passkey-456", path
    end
  end

  test "a refused key shows the tracker's reason and saves nothing" do
    sign_in_as users(:bob)
    stub_tracker({ "index" => [ 200, { status: "failure", error: "invalid token" }.to_json ] }) do
      post site_connection_path(site_slug: "orpheus"), params: { connection: { api_key: "wrong" } }
    end
    assert_response :unprocessable_entity
    assert_includes response.body, "Orpheus said: invalid token"
    assert_not users(:bob).connections.exists?(site: sites(:orpheus))
  end

  test "deleting the account needs the username and removes everything" do
    connection_id, snapshot_id = connections(:alice_redacted).id, snapshots(:alice_new).id
    sign_in_as users(:alice)
    delete settings_account_path, params: { username: "wrong" }
    assert User.exists?(users(:alice).id)

    delete settings_account_path, params: { username: "alice" }
    assert_not User.exists?(users(:alice).id)
    assert_not Connection.exists?(connection_id)
    assert_not Snapshot.exists?(snapshot_id)
  end

  test "every page has the blue bar with the Sherlock mark" do
    sign_in_as users(:alice)
    get dashboard_path
    assert_select "header.topbar span[style*=sherlock-mark]"
  end

  test "an import says how it went in the import card, where it stays" do
    sign_in_as users(:alice)
    file = Tempfile.new([ "export", ".json" ]).tap { _1.write(users(:alice).export.to_json); _1.rewind }
    post settings_import_path, params: { file: Rack::Test::UploadedFile.new(file.path, "application/json") }
    assert_redirected_to settings_data_path(anchor: "import")
    follow_redirect!
    assert_select "form[action='#{settings_import_path}'] [role=status]", text: "Imported 0 updates."

    post settings_import_path, params: { file: Rack::Test::UploadedFile.new(StringIO.new("nope"), "application/json", original_filename: "x.json") }
    follow_redirect!
    assert_select "form[action='#{settings_import_path}'] [role=status]", text: /isn't a Sherlock export/
  end
end
