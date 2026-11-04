require "test_helper"

class PatternsTest < ActiveSupport::TestCase
  GIB = 1024**3

  # Wednesday, 21 October 2026, 12:00 in Berlin (UTC+2).
  setup { travel_to Time.utc(2026, 10, 21, 10) }

  test "hours and days are in the user's time zone, and only single poll changes count per hour" do
    connection = connections(:bob_redacted)
    snapshot connection, "2026-10-20 06:00", 0
    snapshot connection, "2026-10-20 06:55", 2       # Tue 08:55 in Berlin, not 06:55
    snapshot connection, "2026-10-20 11:00", 10      # after a 4 hour gap
    snapshot connection, "2026-10-20 21:30", 11      # Tue 23:30, after a gap
    snapshot connection, "2026-10-20 22:30", 14      # Wed 00:30 in Berlin

    patterns = Time.use_zone("Europe/Berlin") { Patterns.new(connection).tap { _1.by_hour; _1.by_day } }

    assert_equal({ [ 2, 8 ] => 2 * GIB, [ 3, 0 ] => 3 * GIB }, patterns.by_hour)
    assert_equal({ Date.new(2026, 10, 20) => 11 * GIB, Date.new(2026, 10, 21) => 3 * GIB }, patterns.by_day)
  end

  test "weekdays average whole days, summed across trackers, and leave out today" do
    red = connections(:bob_redacted)
    ops = Connection.create!(user: users(:bob), site: sites(:orpheus), credential: "bob-ops-key", external_username: "bob_ops", external_user_id: "71")
    snapshot red, "2026-10-12 10:00", 0
    snapshot red, "2026-10-12 11:00", 4             # Mon 12th: 4
    snapshot red, "2026-10-19 11:00", 6             # Mon 19th: 2 here...
    snapshot ops, "2026-10-19 10:00", 0
    snapshot ops, "2026-10-19 11:00", 4             # ...and 4 here
    snapshot red, "2026-10-21 09:00", 16            # today

    weekdays = Time.use_zone("Europe/Berlin") { Patterns.new([ red, ops ]).by_weekday }

    assert_equal({ 1 => 5 * GIB }, weekdays)
  end

  private
    def snapshot(connection, utc, gib)
      time = Time.find_zone("UTC").parse(utc)
      connection.snapshots.create!(uploaded: gib * GIB, downloaded: 0, created_at: time, updated_at: time)
    end
end
