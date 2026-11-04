class PinnedComparison < ApplicationRecord
  STATS = {
    "buffer" => "Buffer", "uploaded" => "Uploaded", "downloaded" => "Downloaded", "ratio" => "Ratio",
    "interval_ratio" => "Ratio per hour or day", "seeding" => "Seeding", "leeching" => "Leeching",
    "snatched" => "Snatched", "uploads" => "Torrents uploaded", "forum_posts" => "Forum posts",
    "torrent_comments" => "Torrent comments"
  }.freeze

  belongs_to :user

  enum :stat, STATS.keys.index_by(&:itself)
  enum :range, History::RANGES.index_by(&:itself), prefix: true

  scope :chronological, -> { order(:created_at, :id) }

  # Pinning a chart twice keeps the one pin. The ids are sorted, so the same trackers picked in
  # another order are the same chart.
  def self.pin!(stat:, range:, is_per_interval:, connection_ids:)
    attributes = { stat:, range:, is_per_interval:, connection_ids: connection_ids.sort }
    where(attributes.except(:connection_ids)).find_by("connection_ids = ARRAY[?]::bigint[]", attributes[:connection_ids]) || create!(attributes)
  end

  # The user's trackers that are still around. A removed one drops out of the chart.
  def connections
    user.connections.includes(:site).ordered.where(id: connection_ids)
  end

  def title
    "#{STATS.fetch(stat)}#{" per interval" if is_per_interval? && stat != "interval_ratio"}"
  end

  def compare_params
    { stat:, range:, mode: is_per_interval? ? "interval" : "total", ids: connection_ids }
  end
end
