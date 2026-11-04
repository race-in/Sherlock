module ApplicationHelper
  IEC_UNITS = %w[B KiB MiB GiB TiB PiB].freeze
  SI_UNITS = %w[B KB MB GB TB PB].freeze

  # Rounded size in the user's unit, with the exact byte count on hover.
  def bytes(value, signed: false)
    return tag.span("—", class: "text-muted") if value.nil?

    tag.span(human_bytes(value, signed:), class: "num", title: "#{number_with_delimiter(value)} bytes")
  end

  def human_bytes(value, signed: false)
    si = Current.user&.byte_unit_si?
    base = si ? 1000 : 1024
    units = si ? SI_UNITS : IEC_UNITS
    size = value.abs.to_f
    exponent = size.zero? ? 0 : [ (Math.log(size) / Math.log(base)).floor, units.size - 1 ].min
    number = size / base**exponent
    text = "#{number.round(number < 10 && exponent.positive? ? 2 : 1).to_s.sub(/\.0\z/, "")} #{units[exponent]}"
    sign = signed ? (value.positive? ? "+" : value.negative? ? "−" : "") : (value.negative? ? "−" : "")
    "#{sign}#{text}"
  end

  # Says which buffer the numbers show, so a screenshot isn't ambiguous.
  def buffer_label
    Current.user&.buffer_basis_required_ratio? ? "Buffer at required ratio" : "Buffer"
  end

  # A byte change, green when up and red when down. Those two colors mean nothing else.
  def byte_change(value)
    return tag.span("—", class: "text-muted") if value.nil?

    tag.span(human_bytes(value, signed: true), class: [ "num", change_class(value) ], title: "#{number_with_delimiter(value)} bytes")
  end

  def ratio(value)
    value.nil? ? tag.span("—", class: "text-muted") : tag.span(format("%.2f", value), class: "num")
  end

  def ratio_change(value)
    return tag.span("—", class: "text-muted") if value.nil?

    tag.span(format("%+.2f", value).sub("-", "−"), class: [ "num", change_class(value) ])
  end

  def count(value)
    value.nil? ? tag.span("—", class: "text-muted") : tag.span(number_with_delimiter(value), class: "num")
  end

  def change_class(value)
    if value.positive? then "text-up"
    elsif value.negative? then "text-down"
    else "text-muted"
    end
  end

  STATUS_TAGS = {
    "ok" => [ "tag-up", "OK" ],
    "failing" => [ "tag-down", "Failing" ],
    "needs_key" => [ "tag-warn", "Needs key" ],
    "needs_check" => [ "tag-warn", "Needs check" ],
    "paused" => [ "tag-neutral", "Paused" ]
  }.freeze

  def status_tag(connection)
    css, label = STATUS_TAGS.fetch(connection.status)
    tag.span(label, class: css)
  end

  # The tracker's favicon, saved in app/assets/images/sites/<slug>.png, or its initial if there isn't one.
  def site_mark(site, size: "size-6")
    icon = "sites/#{site.slug}.png"
    return image_tag(icon, alt: "", class: "#{size} shrink-0 rounded-md object-contain") if Rails.application.assets.load_path.find(icon)

    tag.span(site.monogram, class: "#{size} inline-flex shrink-0 items-center justify-center rounded-md bg-accent-soft font-mono text-[10px] font-medium text-accent", aria: { hidden: true })
  end

  def time_ago(time)
    return "never" if time.nil?

    tag.time("#{time_ago_in_words(time)} ago", datetime: time.iso8601, title: l(time.in_time_zone, format: :long))
  end

  # The Sherlock silhouette, filled with the text color, so one white PNG works on the blue bar and
  # anywhere else. Hover a while and the pipe smokes.
  def sherlock_mark(css = "h-5")
    mask = "url(#{image_path("sherlock-mark.png")}) center / contain no-repeat"
    tag.span(class: "sherlock-mark relative inline-block shrink-0 #{css}", aria: { hidden: true }, style: "aspect-ratio: 102 / 96") do
      safe_join([
        tag.span(class: "absolute inset-0 bg-current", style: "mask: #{mask}; -webkit-mask: #{mask}"),
        *Array.new(3) { tag.span(class: "smoke") }
      ])
    end
  end

  def clock(time)
    time&.in_time_zone&.strftime("%H:%M")
  end

  def nav_link(label, path, icon:, active: current_page?(path), trailing: nil)
    link_to path, class: "nav-link", aria: { current: ("page" if active) } do
      safe_join([ tag.i(class: "bi bi-#{icon} text-[15px] text-muted"), tag.span(label, class: "flex-1 truncate"), trailing ].compact)
    end
  end

  RANGE_LABELS = { "day" => "24 hours", "week" => "7 days", "month" => "30 days", "quarter" => "90 days", "year" => "1 year", "all" => "All time" }.freeze

  # The three short ranges are links. The longer ones share a select, which opens the system picker
  # on a phone. The select is invisible over its label and 16px, so iOS doesn't zoom in on tap.
  def range_picker(current)
    short, long = History::RANGES.first(3), History::RANGES.drop(3)
    links = short.map do |range|
      link_to RANGE_LABELS[range], url_for(range:),
        class: [ "rounded-md px-2.5 py-1", range == current ? active_range_class : "text-muted hover:text-ink" ],
        aria: { current: ("true" if range == current) }
    end
    more = form_with url: request.path, method: :get, data: { controller: "autosubmit" },
      class: [ "relative flex items-center gap-1 rounded-md px-2.5 py-1 focus-within:ring-2 focus-within:ring-accent/40",
               long.include?(current) ? active_range_class : "text-muted hover:text-ink" ] do
      safe_join([
        tag.span(long.include?(current) ? RANGE_LABELS[current] : "More"),
        tag.i(class: "bi bi-chevron-down text-[10px]", aria: { hidden: true }),
        select_tag(:range, options_for_select([ [ "More", "" ] ] + long.map { [ RANGE_LABELS[_1], _1 ] }, selected: long.include?(current) ? current : "", disabled: ""),
          id: nil, class: "absolute inset-0 cursor-pointer appearance-none text-base opacity-0", aria: { label: "More ranges" },
          data: { action: "autosubmit#submit" })
      ])
    end
    tag.nav(safe_join(links << more), class: "inline-flex items-center rounded-lg border border-line bg-surface p-0.5 text-sm whitespace-nowrap", aria: { label: "Range" })
  end

  # A solid blue pill for the active range, as the old Day/Week/Month links did.
  def active_range_class
    "bg-accent font-medium text-accent-ink"
  end

  def time_zone_options
    ActiveSupport::TimeZone.all.map { [ _1.to_s, _1.tzinfo.identifier ] }.uniq(&:last)
  end

  def chart_points(history, stat, group:, per_interval: false)
    history.series(stat, per_interval:).map { |time, value| { group:, date: time.iso8601, value: value.to_f } }
  end

  # Each tracker's chart color, by the name its charts group under.
  def tracker_colors(connections)
    connections.to_h { |connection| [ connection.site.display_name, connection.display_color ] }
  end

  # Placeholder history for a chart whose tracking began inside the range. Shapes: "total" never
  # goes down, "level" wanders, "interval" is one value per hour or day.
  def chart_sample(history, shape)
    { from: history.starts_at.iso8601, since: history.first_snapshot_at.iso8601, shape: } if history.started_late?
  end

  # A small step line of a stat over the last 7 days, drawn inline so dashboard cards don't need the
  # chart bundle. Time runs along x, so a tracker added mid-week only fills the right part.
  def sparkline(connection, stat = :buffer, days: 7)
    series = connection.history("week").series(stat)
    return if series.size < 2

    from, to = days.days.ago.to_f, Time.current.to_f
    low, high = series.map(&:last).minmax
    span = (high - low).nonzero? || 1
    points = series.map { |time, value| [ (100 * (time.to_f - from) / (to - from)).clamp(0, 100).round(2), (30 - 28 * (value - low) / span).round(2) ] }
    line = "M#{points.first.join(",")}" + points.drop(1).map { |x, y| "H#{x}V#{y}" }.join + "H100"
    tag.svg(viewBox: "0 0 100 32", preserveAspectRatio: "none", class: "h-9 w-full text-accent", aria: { hidden: true }) do
      tag.path(d: "#{line}V32H#{points.first.first}Z", fill: "currentColor", "fill-opacity": 0.12) +
        tag.path(d: line, fill: "none", stroke: "currentColor", "stroke-width": 1.5, "vector-effect": "non-scaling-stroke")
    end
  end

  def weekday_name(wday)
    I18n.t("date.abbr_day_names")[wday]
  end

  HOURS = (0..23).map { format("%02d", _1) }.freeze

  # Heatmaps take { x:, y:, value: } cells, the label order of both axes, and the axis names shown in
  # the tooltip.
  def hour_heatmap(patterns)
    points = patterns.by_hour.map { |(wday, hour), value| { x: HOURS[hour], y: weekday_name(wday), value: } }
    { points:, labels: { x: HOURS, y: Patterns::WEEKDAYS.map { weekday_name(_1) }, x_title: "Hour", y_title: "Day" } }
  end

  def calendar_heatmap(patterns)
    weeks = (patterns.starts_at.to_date..Time.zone.today).step(7).map { l(_1.beginning_of_week, format: "%b %-d") }
    points = patterns.by_day.map { |date, value| { x: l(date.beginning_of_week, format: "%b %-d"), y: weekday_name(date.wday), value: } }
    { points:, labels: { x: weeks, y: Patterns::WEEKDAYS.map { weekday_name(_1) }, x_title: "Week of", y_title: "Day" } }
  end

  def weekday_points(patterns)
    patterns.by_weekday.map { |wday, value| { group: weekday_name(wday), value: } }
  end

  # Upload per tracker over a range. Trackers without upload in it are left out of the donut.
  def upload_share_points(connections, range)
    since = History::DURATIONS[range]&.ago || Time.at(0)
    connections.filter_map do |connection|
      uploaded = connection.change(since:)&.uploaded
      { group: connection.site.display_name, value: uploaded } if uploaded&.positive?
    end
  end

  def chart_unit(stat)
    if Snapshot::BYTE_STATS.include?(stat.to_sym) then "bytes"
    elsif stat.to_sym.in?(%i[ratio interval_ratio]) then "ratio"
    else "count"
    end
  end
end
