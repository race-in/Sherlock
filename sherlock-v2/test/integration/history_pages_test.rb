require "test_helper"

class HistoryPagesTest < ActionDispatch::IntegrationTest
  setup do
    @connection = connections(:alice_redacted)
    # With the two fixture snapshots, 60 hours in the last week.
    (3..60).each do |hours|
      @connection.snapshots.create!(uploaded: 10.gigabytes + hours, downloaded: 5.gigabytes, ratio: 2.0, created_at: hours.hours.ago)
    end
    sign_in_as users(:alice)
  end

  test "the history table shows 50 rows a page, newest first, and the CSV has every row" do
    get connection_history_path(@connection, range: "week")
    assert_select "tbody tr", 50
    newest = css_select("tbody tr td").first.text
    assert_select "a[rel=next][href=?]", connection_history_path(@connection, range: "week", page: 2)
    assert_select "a[rel=prev]", 0

    get connection_history_path(@connection, range: "week", page: 2)
    assert_select "tbody tr", 10
    assert_not_includes css_select("tbody tr td").map(&:text), newest
    assert_select "a[rel=prev]"
    assert_select "a[rel=next]", 0

    get connection_history_path(@connection, range: "week", page: 99)
    assert_select "tbody tr", 10

    get connection_history_path(@connection, range: "week", format: :csv)
    assert_equal 61, response.body.lines.size
  end
end
