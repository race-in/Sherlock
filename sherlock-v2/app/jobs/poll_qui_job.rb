class PollQuiJob < ApplicationJob
  discard_on ActiveJob::DeserializationError

  # Reads all of the user's quis together, so each tracker gets one snapshot from all of them.
  def perform(user)
    Current.set(tracker_purpose: "poll") { QuiConnection.poll!(user) }
  end
end
