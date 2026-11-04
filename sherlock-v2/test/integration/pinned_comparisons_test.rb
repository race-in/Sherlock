require "test_helper"

class PinnedComparisonsTest < ActionDispatch::IntegrationTest
  setup do
    @connection = connections(:alice_redacted)
    sign_in_as users(:alice)
  end

  test "a pinned chart stays on the compare page until it's unpinned" do
    assert_difference -> { users(:alice).pinned_comparisons.count } do
      post comparison_pins_path, params: { stat: "ratio", range: "month", mode: "interval", ids: [ @connection.id ] }
      post comparison_pins_path, params: { stat: "ratio", range: "month", mode: "interval", ids: [ @connection.id ] }
    end
    pin = users(:alice).pinned_comparisons.find_by!(stat: "ratio")
    assert_equal [ "month", true, [ @connection.id ] ], [ pin.range, pin.is_per_interval, pin.connection_ids ]

    get comparison_path(stat: "buffer")
    assert_select "h2", text: "Pinned"
    assert_select "h2.eyebrow", text: "Ratio per interval"
    assert_select "form[action=?]", comparison_pin_path(pin)

    delete comparison_pin_path(pin)
    get comparison_path(stat: "buffer")
    assert_select "h2.eyebrow", text: "Ratio per interval", count: 0
  end

  test "a stat the compare page doesn't offer can't be pinned" do
    assert_no_difference -> { PinnedComparison.count } do
      post comparison_pins_path, params: { stat: "bonus_points", range: "week", ids: [ @connection.id ] }
    end
  end
end
