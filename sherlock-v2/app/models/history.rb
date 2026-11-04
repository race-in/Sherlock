# A connection's snapshots over a range, grouped into hours (day and week) or days (longer), with
# each interval's change against the one before. Times are in Time.zone, which is the user's.
class History
  RANGES = %w[day week month quarter year all].freeze
  DURATIONS = { "day" => 1.day, "week" => 7.days, "month" => 30.days, "quarter" => 90.days, "year" => 365.days }.freeze
  STATS = %i[uploaded downloaded buffer ratio bonus_points seeding leeching snatched uploads forum_posts torrent_comments].freeze
  COLUMNS = %i[created_at uploaded downloaded ratio bonus_points seeding leeching snatched uploads forum_posts torrent_comments required_ratio].freeze

  Point = Data.define(:time, :values, :deltas) do
    def [](stat) = values[stat]
    def delta(stat) = deltas[stat]

    # Upload divided by download within this interval, the old Sherlock's "hourly ratio". nil when
    # nothing was downloaded, since the ratio has no value then.
    def interval_ratio
      uploaded, downloaded = delta(:uploaded), delta(:downloaded)
      uploaded.fdiv(downloaded) if uploaded && downloaded&.positive?
    end
  end

  # since: is_partial is true when the history doesn't reach back that far, so the change is since
  # the first snapshot instead.
  Change = Data.define(:uploaded, :downloaded, :buffer, :ratio, :is_partial)

  def self.change(connection, since:)
    latest = connection.latest_snapshot or return
    base = connection.snapshots.where(created_at: ..since).order(created_at: :desc).first
    is_partial = base.nil?
    base ||= connection.snapshots.chronological.first

    Change.new(
      uploaded: latest.uploaded - base.uploaded,
      downloaded: latest.downloaded - base.downloaded,
      buffer: latest.buffer - base.buffer,
      ratio: (latest.ratio - base.ratio if latest.ratio && base.ratio),
      is_partial:
    )
  end

  attr_reader :range

  def self.normalize_range(range)
    RANGES.include?(range.to_s) ? range.to_s : "week"
  end

  def initialize(connection, range:)
    @connection = connection
    @range = self.class.normalize_range(range)
  end

  def interval
    %w[day week].include?(range) ? :hour : :day
  end

  def starts_at
    DURATIONS[range]&.ago
  end

  def points
    @points ||= begin
      previous = baseline && values_of(baseline)
      buckets.map do |time, row|
        values = values_of(row)
        deltas = STATS.index_with { |stat| previous && values[stat] && previous[stat] && values[stat] - previous[stat] }
        previous = values
        Point.new(time:, values:, deltas:)
      end
    end
  end

  def series(stat, per_interval: false)
    points.filter_map do |point|
      value = if stat == :interval_ratio then point.interval_ratio
      elsif per_interval then point.delta(stat)
      else point[stat]
      end
      [ point.time, value ] unless value.nil?
    end
  end

  def average_upload_delta
    deltas = points.filter_map { _1.delta(:uploaded) }
    deltas.sum.fdiv(deltas.size) if deltas.any?
  end

  # The old Sherlock's "better than your average hour".
  def above_average?(point)
    average = average_upload_delta
    delta = point.delta(:uploaded)
    average && delta && delta.positive? && delta > average
  end

  # When tracking began well after the range starts, charts fill the gap with placeholder history.
  def started_late?
    starts_at.present? && first_snapshot_at.present? && first_snapshot_at - starts_at > DURATIONS[range] / 10
  end

  def first_snapshot_at
    return @first_snapshot_at if defined?(@first_snapshot_at)
    @first_snapshot_at = @connection.snapshots.minimum(:created_at)
  end

  def reports?(stat)
    points.any? { !_1[stat].nil? }
  end

  # Raw bytes and full precision, so a spreadsheet can do its own maths.
  def to_csv
    CSV.generate do |csv|
      csv << [ "time", *STATS, *STATS.first(3).map { "#{_1}_change" }, "interval_ratio" ]
      points.each do |point|
        csv << [ point.time.iso8601, *STATS.map { point[_1] }, *STATS.first(3).map { point.delta(_1) }, point.interval_ratio ]
      end
    end
  end

  private
    def scope
      starts_at ? @connection.snapshots.where(created_at: starts_at..) : @connection.snapshots
    end

    # The snapshot just before the range, so the first interval has a change too.
    def baseline
      return @baseline if defined?(@baseline)
      @baseline = starts_at && @connection.snapshots.where(created_at: ...starts_at).order(created_at: :desc).pick(*COLUMNS)
    end

    def buckets
      scope.chronological.pluck(*COLUMNS)
        .group_by { |row| bucket_for(row.first) }
        .transform_values(&:last)
    end

    def bucket_for(time)
      time = time.in_time_zone
      interval == :hour ? time.beginning_of_hour : time.beginning_of_day
    end

    def values_of(row)
      created_at, uploaded, downloaded, ratio, bonus_points, seeding, leeching, snatched, uploads, forum_posts, torrent_comments, required_ratio = row
      { created_at:, uploaded:, downloaded:, buffer: Snapshot.buffer(uploaded, downloaded, required_ratio), ratio:, bonus_points:, seeding:, leeching:, snatched:, uploads:, forum_posts:, torrent_comments: }
    end
end
