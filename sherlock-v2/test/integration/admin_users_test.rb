require "test_helper"

class AdminUsersTest < ActionDispatch::IntegrationTest
  test "the invite tree charts the last 30 days of new users, with quiet days as 0, and the running total up to now" do
    travel_to Time.utc(2026, 10, 28, 12) do
      User.where.not(id: users(:admin, :alice).map(&:id)).update_all(created_at: Time.current)
      users(:admin).update_columns(created_at: 3.days.ago, time_zone: "UTC")
      users(:alice).update_columns(created_at: 3.days.ago)
      others = User.count - 2

      sign_in_as users(:admin)
      get admin_users_path
      charts = css_select("[data-chart-points-value]").to_h { [ _1["data-chart-title-value"], JSON.parse(_1["data-chart-points-value"]).map { |point| point["value"] } ] }
      assert_equal [ 0 ] * 26 + [ 2, 0, 0, others ], charts["New users per day"]
      assert_equal [ 0 ] * 26 + [ 2, 2, 2, 2 + others, 2 + others ], charts["Users in total"]

      users(:admin).update_columns(created_at: 40.days.ago)
      get admin_users_path(range: "all")
      charts = css_select("[data-chart-points-value]").to_h { [ _1["data-chart-title-value"], JSON.parse(_1["data-chart-points-value"]).map { |point| point["value"] } ] }
      assert_equal [ 1 ] + [ 0 ] * 36 + [ 1, 0, 0, others ], charts["New users per day"]
    end
  end
end
