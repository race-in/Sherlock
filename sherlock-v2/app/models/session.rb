# A signed-in device. It lasts while it's used: each request at most an hour after the last one moves
# updated_at, which Settings → Account shows as "Last active", and one idle for IDLE_TIMEOUT is over.
class Session < ApplicationRecord
  IDLE_TIMEOUT = 90.days
  TOUCH_EVERY = 1.hour

  belongs_to :user

  scope :active, -> { where(updated_at: IDLE_TIMEOUT.ago..) }
  scope :expired, -> { where(updated_at: ...IDLE_TIMEOUT.ago) }

  # True when it moved, so the cookie can be renewed too.
  def touch_if_stale
    updated_at < TOUCH_EVERY.ago && touch
  end
end
