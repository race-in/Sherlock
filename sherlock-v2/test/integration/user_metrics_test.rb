require "test_helper"

class UserMetricsTest < ActionDispatch::IntegrationTest
  test "a token scrapes only its own user's latest stats, and leaves out what isn't reported" do
    connections(:bob_redacted).snapshots.create!(uploaded: 777, downloaded: 1)
    token = users(:alice).regenerate_metrics_token!

    get users_metrics_path, headers: { "Authorization" => "Bearer #{token}" }

    assert_response :success
    assert_equal "text/plain; version=0.0.4; charset=utf-8", response.content_type
    assert_includes response.body, %(sherlock_uploaded_bytes{site="redacted"} 16106127360\n)
    assert_includes response.body, %(sherlock_buffer_bytes{site="redacted"} 9663676416\n)
    assert_includes response.body, %(sherlock_ratio{site="redacted"} 2.5\n)
    assert_includes response.body, %(sherlock_seeding{site="redacted"} 12\n)
    assert_includes response.body, %(sherlock_tracker_ok{site="redacted"} 1\n)
    assert_not_includes response.body, "sherlock_bonus_points", "not reported is left out, not 0"
    assert_not_includes response.body, "777"
    assert_not_includes response.body, "alice-secret-key"
  end

  test "no token, a wrong one, a replaced one, a revoked one or a disabled user's is refused" do
    alice = users(:alice)
    old = alice.regenerate_metrics_token!
    current = alice.regenerate_metrics_token!

    [ nil, "Bearer nope", "Bearer #{old}" ].each do |header|
      get users_metrics_path, headers: { "Authorization" => header }.compact
      assert_response :unauthorized, header.inspect
    end

    alice.disable!
    get users_metrics_path, headers: { "Authorization" => "Bearer #{current}" }
    assert_response :unauthorized

    alice.enable!
    alice.revoke_metrics_token!
    get users_metrics_path, headers: { "Authorization" => "Bearer #{current}" }
    assert_response :unauthorized
  end

  test "the token is shown once, when it's made, and only a digest is stored" do
    sign_in_as users(:alice)
    post settings_developer_metrics_token_path
    assert_response :success
    token = css_select("[data-clipboard-text-value]").sole["data-clipboard-text-value"]
    assert_match(/\Asherlock_\w{32}\z/, token)
    assert_not_includes users(:alice).reload.attributes.values.compact.map(&:to_s), token

    get settings_developer_path
    assert_not_includes response.body, token

    get users_metrics_path, headers: { "Authorization" => "Bearer #{token}" }
    assert_response :success
  end

  test "Sherlock's own metrics are only for direct requests from the private network" do
    get "/metrics"
    assert_response :success

    get "/metrics", headers: { "X-Forwarded-For" => "10.0.0.1" }
    assert_response :not_found, "came through the public proxy"

    get "/metrics", env: { "REMOTE_ADDR" => "203.0.113.9" }
    assert_response :not_found
  end
end
