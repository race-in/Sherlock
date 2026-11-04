require "test_helper"

class TrackerSettingsTest < ActionDispatch::IntegrationTest
  test "the tracker settings page shows the color picker" do
    sign_in_as users(:alice)
    get settings_connection_path(connections(:alice_redacted))
    assert_response :success
    assert_match "hex-color-picker", response.body
  end

  test "picking and resetting a tracker color" do
    sign_in_as users(:alice)
    patch settings_connection_color_path(connections(:alice_redacted)), params: { connection: { color: "#1F7FA6" } }
    assert_redirected_to settings_connection_path(connections(:alice_redacted))
    assert_equal "#1f7fa6", connections(:alice_redacted).reload.display_color

    patch settings_connection_color_path(connections(:alice_redacted)), params: { connection: { color: "chartreuse" } }
    assert_equal "#1f7fa6", connections(:alice_redacted).reload.color

    patch settings_connection_color_path(connections(:alice_redacted)), params: { connection: { color: "" } }
    assert_nil connections(:alice_redacted).reload.color
    assert_equal sites(:redacted).default_color, connections(:alice_redacted).display_color
  end

  test "dragging trackers sets the order of the sidebar, and only of your own" do
    alice = users(:alice)
    red = connections(:alice_redacted)
    added = %i[orpheus gazellegames].map { alice.connections.create!(site: sites(_1), credential: "k", external_username: "a", external_user_id: "1") }
    ops, ggn = added
    assert_equal [ red, ops, ggn ], alice.connections.ordered.to_a, "a new tracker goes to the end, not in alphabetical order"
    bob = connections(:bob_redacted).tap { _1.update_column(:position, 5) }

    sign_in_as alice
    patch settings_tracker_order_path, params: { ids: [ ggn.id, bob.id, red.id ] }
    assert_response :no_content
    assert_equal [ ggn, red, ops ], alice.connections.ordered.to_a, "a tracker left out keeps its place after the others"
    assert_equal 5, bob.reload.position

    get dashboard_path
    assert_equal %w[GazelleGames Redacted Orpheus], css_select("nav[aria-label=Main] a.nav-link[href^='/trackers/'] span.flex-1").map { _1.text.strip }.uniq
  end

  test "choosing short tracker names shows the short codes, only to you" do
    sign_in_as users(:alice)
    patch settings_preferences_path, params: { user: { is_tracker_name_short: "1" } }
    get connection_path(connections(:alice_redacted))
    assert_select "nav[aria-label=Main] span.flex-1", text: "RED"
    assert_select "h1", text: "RED"

    sign_in_as users(:bob)
    get connection_path(connections(:bob_redacted))
    assert_select "h1", text: "Redacted"
  end

  test "the required-ratio buffer is what you can download before falling below it, but not in metrics" do
    alice = users(:alice)
    sign_in_as alice
    patch settings_preferences_path, params: { user: { buffer_basis: "required_ratio" } }

    # 15 GiB uploaded / 0.6 required = 25 GiB allowed, minus 6 GiB downloaded. At 1.0 it's 9 GiB.
    get connection_path(connections(:alice_redacted))
    assert_select ".card", text: /Buffer at required ratio/ do
      assert_select "span[title=?]", "#{20_401_094_656.to_fs(:delimited)} bytes"
    end

    token = alice.regenerate_metrics_token!
    get users_metrics_path, headers: { "Authorization" => "Bearer #{token}" }
    assert_includes response.body, %(sherlock_buffer_bytes{site="redacted"} 9663676416\n), "scrapers keep uploaded minus downloaded"
  end

  test "Test now leaves a tracker alone that was asked in the last 15 minutes" do
    sign_in_as users(:alice)
    connection = connections(:alice_redacted)
    connection.update!(polled_at: 2.minutes.ago)
    stub_tracker({}) do |requests|
      post settings_connection_poll_path(connection)
      assert_empty requests
    end
    assert_redirected_to settings_connection_path(connection)
    assert_match "Try again later", flash[:notice]
  end
end
