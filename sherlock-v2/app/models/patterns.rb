# When upload happens, over the last WEEKS weeks of one or more connections. Each snapshot's upload
# is its change against the snapshot before it, counted at the later snapshot's time in Time.zone,
# which is the user's. With several connections, the same hour or day is summed across them.
class Patterns
  WEEKS = 26
  # Mon first. Ruby's wday counts from Sunday.
  WEEKDAYS = [ 1, 2, 3, 4, 5, 6, 0 ].freeze

  def initialize(connections)
    @connections = Array(connections)
  end

  def starts_at
    @starts_at ||= (Time.zone.today - (WEEKS * 7 - 1)).beginning_of_week.in_time_zone
  end

  # { Date => bytes } for every day with data.
  def by_day
    @by_day ||= deltas.each_with_object(Hash.new(0)) { |(time, bytes, _), days| days[time.to_date] += bytes }
  end

  # { wday => average bytes per day }. Today is left out, because it isn't over yet.
  def by_weekday
    days = by_day.except(Time.zone.today).group_by { |date, _| date.wday }
    WEEKDAYS.index_with { |wday| average(days.fetch(wday, []).map(&:last)) }.compact
  end

  # { [wday, hour] => average bytes in that hour }. Only changes across a single poll interval count;
  # after a gap, the change covers many hours and would show up as one tall spike.
  def by_hour
    hours = deltas.each_with_object(Hash.new(0)) do |(time, bytes, gap), sums|
      sums[time.beginning_of_hour] += bytes if gap <= 90.minutes
    end
    hours.group_by { |time, _| [ time.wday, time.hour ] }.transform_values { |rows| average(rows.map(&:last)) }
  end

  def any?
    deltas.any?
  end

  private
    def deltas
      @deltas ||= @connections.flat_map do |connection|
        connection.snapshots.where(created_at: (starts_at - 1.day)..).chronological.pluck(:created_at, :uploaded)
          .each_cons(2).filter_map do |(before, uploaded_before), (time, uploaded)|
            time = time.in_time_zone
            [ time, uploaded - uploaded_before, time - before ] if time >= starts_at
          end
      end
    end

    def average(values)
      values.sum.fdiv(values.size) if values.any?
    end
end
