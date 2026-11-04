require "test_helper"

class QuiSettingsTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  RED = "https://flacsfor.me/abc/announce"

  setup { sign_in_as users(:bob) }

  test "qui is only for the people an admin granted it, like a granted tracker" do
    integrations(:qui).update!(availability: :granted)
    qui = users(:bob).qui_connections.create!(url: "https://qui.example.org", credential: "bob-qui-key", polled_at: Time.current)
    get settings_connections_path
    assert_select "a[href='#{settings_qui_connections_path}']", count: 0
    get settings_qui_connections_path
    assert_response :not_found
    assert_raises(Engines::Error) { QuiConnection.connect!(user: users(:bob), url: "https://qui.example.org", api_key: "k") }
    stub_qui_status(200) do |requests|
      assert_not QuiConnection.poll!(users(:bob))
      assert_empty requests
    end
    assert_enqueued_jobs(0, only: PollQuiJob) { PollAllConnectionsJob.perform_now }

    post admin_user_integration_grants_path(users(:bob)), params: { slug: "qui" }
    assert_response :not_found
    delete session_path
    sign_in_as users(:admin)
    post admin_user_integration_grants_path(users(:bob)), params: { slug: "qui" }
    assert_redirected_to admin_user_path(users(:bob))
    delete session_path
    sign_in_as users(:bob)

    get settings_qui_connections_path
    assert_response :success
    assert_enqueued_jobs(1, only: PollQuiJob) { PollAllConnectionsJob.perform_now }

    integrations(:qui).update!(availability: :off)
    assert_not integrations(:qui).available_to?(users(:admin))
    assert_enqueued_jobs(0, only: PollQuiJob) { PollAllConnectionsJob.perform_now }
    assert QuiConnection.exists?(qui.id), "the qui and its key stay"
  end

  test "connecting qui shows cross-seeds on the dashboard and tracker page, and never the key" do
    torrents = [
      { "tracker" => RED, "content_path" => "/data/a", "size" => 50.megabytes, "uploaded" => 3.gigabytes, "progress" => 1, "state" => "uploading" },
      { "tracker" => "https://other.example/announce", "content_path" => "/data/a", "size" => 50.megabytes, "progress" => 1, "state" => "stalledUP" }
    ]
    get settings_connections_path
    assert_select "a[href='#{settings_qui_connections_path}']"
    get settings_qui_connections_path
    assert_response :success

    stub_qui("192.168.1.10" => { 1 => torrents }) do
      post settings_qui_connections_path, params: { qui: { url: "http://192.168.1.10:7476", api_key: "qui-secret-key" } }
    end
    assert_redirected_to settings_qui_connections_path

    [ settings_qui_connections_path, dashboard_path, connection_path(connections(:bob_redacted)) ].each do |path|
      get path
      assert_not_includes response.body, "qui-secret-key", path
    end
    assert_includes response.body, "Cross-seeding"
    assert_select "p", text: /1\s+of 1 seeding/
    # Nothing from a day ago yet, so no change to show.
    assert_select "p", text: /—\s+in the last 24 hours/
    connections(:bob_redacted).cross_seed_snapshots.create!(torrents: 1, size: 1, uploaded: 0, cross_seeded: 0,
      cross_seeded_size: 0, cross_seeded_uploaded: 0, created_at: 25.hours.ago)
    get connection_path(connections(:bob_redacted))
    assert_select "p", text: /\+1\s+in the last 24 hours/

    qui = users(:bob).qui_connections.sole
    patch settings_qui_connection_path(qui), params: { qui: { label: " Seedbox " } }
    follow_redirect!
    assert_select "p.font-medium", text: "Seedbox"
    assert_includes response.body, "192.168.1.10:7476"
    patch settings_qui_connection_path(qui), params: { qui: { label: "" } }
    assert_nil qui.reload.label

    delete settings_qui_connection_path(qui)
    assert_empty users(:bob).reload.qui_connections
    assert_equal 2, connections(:bob_redacted).cross_seed_snapshots.count, "removing qui keeps the history"
  end

  test "an unreachable qui shows why and saves nothing" do
    stub_qui_status(404) do
      post settings_qui_connections_path, params: { qui: { url: "http://qui.lan", api_key: "qui-secret-key" } }
    end
    assert_response :unprocessable_entity
    assert_includes response.body, "qui answered with HTTP 404"
    assert_not_includes response.body, "qui-secret-key"
    assert_empty users(:bob).reload.qui_connections
  end

  test "another user's qui can't be removed" do
    alice_qui = users(:alice).qui_connections.create!(url: "http://qui.lan", credential: "alice-qui-key", polled_at: Time.current)
    patch settings_qui_connection_path(alice_qui), params: { qui: { label: "Mine" } }
    assert_response :not_found
    delete settings_qui_connection_path(alice_qui)
    assert_response :not_found
    assert_nil alice_qui.reload.label
    assert QuiConnection.exists?(alice_qui.id)
  end
end
