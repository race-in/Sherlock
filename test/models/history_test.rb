require "test_helper"

class HistoryTest < ActiveSupport::TestCase
  GIB = 1024**3

  test "change since a time uses the last snapshot at or before it" do
    change = connections(:alice_redacted).change(since: 1.day.ago)

    assert_equal 5 * GIB, change.uploaded
    assert_equal 1 * GIB, change.downloaded
    assert_equal 4 * GIB, change.buffer
    assert_equal BigDecimal("0.5"), change.ratio
    assert_not change.is_partial
  end

  test "change reaching past the first snapshot says it is partial" do
    change = connections(:alice_redacted).change(since: 30.days.ago)
    assert change.is_partial
    assert_equal 4 * GIB, change.buffer
  end

  test "points carry each interval's change against the one before, including across the range start" do
    history = connections(:alice_redacted).history("day")

    assert_equal 1, history.points.size
    assert_equal 5 * GIB, history.points.first.delta(:uploaded), "the 3 day old snapshot is the baseline"
    assert_equal 9 * GIB, history.points.first[:buffer]
    assert_equal 5.0, history.points.first.interval_ratio, "upload over download, 5 GiB / 1 GiB"
  end

  test "an interval without download has no ratio and is left out of the series" do
    connection = connections(:alice_redacted)
    connection.snapshots.create!(uploaded: 20 * GIB, downloaded: 6 * GIB, created_at: 1.minute.ago)
    history = connection.history("day")

    assert_nil history.points.last.interval_ratio
    assert_equal 1, history.series(:interval_ratio).size
  end

  test "charts get placeholder history only when tracking began well inside the range" do
    connection = connections(:alice_redacted)

    assert connection.history("month").started_late?, "the first snapshot is 3 days old, 27 days into the range"
    assert_not connection.history("day").started_late?, "a snapshot from before the range covers it"
    assert_not connection.history("all").started_late?

    connection.snapshots.create!(uploaded: 10 * GIB, downloaded: 5 * GIB, created_at: 29.days.ago)
    assert_not connection.history("month").started_late?, "a day late is within a tenth of 30 days"
  end

  test "no snapshots means no change" do
    assert_nil connections(:bob_redacted).change(since: 1.day.ago)
  end
end
