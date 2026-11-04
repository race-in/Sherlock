module CrossSeedsHelper
  # How many more torrents on the tracker are cross-seeded than at the last poll at or before since:,
  # as a colored "+3". A dash while the history doesn't reach back that far.
  def cross_seed_change(connection, since:)
    latest = connection.cross_seed_snapshots.chronological.last
    base = connection.cross_seed_snapshots.where(created_at: ..since).order(created_at: :desc).first
    return tag.span("—", class: "text-muted") unless latest && base

    change = latest.cross_seeded - base.cross_seeded
    tag.span(format("%+d", change).sub("-", "−"), class: [ "num", change_class(change) ])
  end

  # Chart points for the torrents qui saw seeding on a tracker and how many of them are cross-seeded,
  # the last poll in each of the history's intervals.
  def cross_seed_points(connection, history)
    rows = connection.cross_seed_snapshots.chronological
    rows = rows.where(created_at: history.starts_at..) if history.starts_at
    rows.group_by { _1.created_at.in_time_zone.public_send(:"beginning_of_#{history.interval}") }.flat_map do |time, snapshots|
      last = snapshots.last
      [ { group: "Seeding", date: time.iso8601, value: last.torrents }, { group: "Cross-seeded", date: time.iso8601, value: last.cross_seeded } ]
    end
  end
end
