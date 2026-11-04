# What qui saw for one tracker in one poll. See QuiConnection#record.
class CrossSeedSnapshot < ApplicationRecord
  belongs_to :connection

  scope :chronological, -> { order(:created_at) }

  # Only ever added. Rows go away through the ON DELETE CASCADE on connections.
  def readonly?
    persisted? || super
  end
end
