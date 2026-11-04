class Current < ActiveSupport::CurrentAttributes
  attribute :session
  # Why tracker requests go out right now, see Engines::Http.purpose.
  attribute :tracker_purpose
  delegate :user, to: :session, allow_nil: true
end
