class PollConnectionJob < ApplicationJob
  # One poll at a time per tracker. Engines::Http also spaces every request to a site, from jobs and
  # pages together, and holds them back while the site is paused.
  limits_concurrency to: 1, key: ->(connection) { connection.site_id }, duration: 5.minutes

  discard_on ActiveJob::DeserializationError

  # Sherlock held back: the site is paused or busy, or the tracker asked it to slow down. The next
  # hourly poll tries again; nothing retries sooner.
  discard_on Engines::Withheld

  def perform(connection)
    Current.set(tracker_purpose: "poll") { connection.poll! }
  end
end
