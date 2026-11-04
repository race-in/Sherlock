class Snapshot < ApplicationRecord
  STATS = %i[uploaded downloaded buffer ratio bonus_points seeding leeching snatched hit_and_runs uploads forum_posts torrent_comments].freeze
  BYTE_STATS = %i[uploaded downloaded buffer].freeze

  belongs_to :connection
  belongs_to :created_by_user, class_name: "User", optional: true

  enum :source, { api: "api", manual: "manual", csv_import: "csv_import", json_import: "json_import" }, prefix: true

  validates :note, length: { maximum: 500 }, allow_nil: true

  scope :chronological, -> { order(:created_at) }

  # Uploaded minus downloaded. With the user's required-ratio preference, what they can still
  # download before falling below the required ratio; a tracker that reports none uses 1.0.
  # Without a signed-in user, as in /users/metrics, always uploaded minus downloaded. Derived,
  # never stored.
  def self.buffer(uploaded, downloaded, required_ratio)
    if Current.user&.buffer_basis_required_ratio? && required_ratio&.positive?
      (uploaded / required_ratio).floor - downloaded
    else
      uploaded - downloaded
    end
  end

  def buffer
    self.class.buffer(uploaded, downloaded, required_ratio)
  end

  # Snapshots are only ever added. Rows go away through the ON DELETE CASCADE on connections.
  def readonly?
    persisted? || super
  end
end
