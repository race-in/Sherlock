require "yabeda/rails"
require "yabeda/activejob"

Yabeda.configure do
  Yabeda::Rails.config.ignore_actions = %w[Rails::HealthController#show]
  Yabeda::ActiveJob.install!

  # Tags stay low-cardinality: site slugs, statuses, purposes and reasons, never a user, connection,
  # URL or host. Requests from pages count in the web process's /metrics, polls in the worker's.
  group :sherlock do
    counter :polls_total, comment: "Tracker polls by site and result", tags: %i[site result]
    histogram :poll_duration_seconds, comment: "One poll against one tracker, all its requests", tags: %i[site],
      buckets: [ 0.25, 0.5, 1, 2, 5, 10, 30 ]
    counter :tracker_requests_total,
      comment: "Requests sent to tracker APIs (site \"qui\" for qui) by HTTP status or network error, why they were sent, and whose key",
      tags: %i[site status purpose key_owner]
    histogram :tracker_request_duration_seconds, comment: "One request to a tracker API", tags: %i[site],
      buckets: [ 0.1, 0.25, 0.5, 1, 2, 5, 15 ]
    histogram :tracker_request_wait_seconds, comment: "How long a request waited for its site's next slot", tags: %i[site],
      buckets: [ 0, 0.5, 1, 2, 5, 15, 30, 60 ]
    counter :tracker_requests_withheld_total, comment: "Requests Sherlock didn't send because the site was paused or busy",
      tags: %i[site reason purpose]
    gauge :site_paused, comment: "1 while Sherlock sends nothing to the site, by why", tags: %i[site reason]
    gauge :site_failure_streak, comment: "Tracker errors (5xx, timeouts) in a row", tags: %i[site]
    gauge :site_capacity, comment: "How many members the site's request interval leaves room for", tags: %i[site]
    gauge :connections, comment: "Connections by site and status", tags: %i[site status]

    collect do
      next unless Connection.table_exists?

      counts = Connection.joins(:site).group("sites.slug", :status).count
      # Every pair, not only the ones with rows: a gauge keeps its last value until set again,
      # so a status that just emptied would otherwise never drop to zero.
      sites = Site.where.not(engine: nil).to_a
      sites.map(&:slug).product(Connection.statuses.keys).each do |site, status|
        sherlock.connections.set({ site:, status: }, counts.fetch([ site, status ], 0))
      end
      sites.each do |site|
        Site.pause_reasons.each_key do |reason|
          sherlock.site_paused.set({ site: site.slug, reason: }, site.paused? && site.pause_reason == reason ? 1 : 0)
        end
        sherlock.site_failure_streak.set({ site: site.slug }, site.failure_streak)
        sherlock.site_capacity.set({ site: site.slug }, site.capacity)
      end
    end
  end
end

# Connection#poll! reports every poll and Engines::Http every request through Rails.event.
Rails.event.subscribe(Class.new do
  def emit(event)
    payload = event[:payload]
    case event[:name]
    when "poll.succeeded", "poll.failed"
      Yabeda.sherlock.polls_total.increment({ site: payload[:site], result: event[:name].delete_prefix("poll.") })
      Yabeda.sherlock.poll_duration_seconds.measure({ site: payload[:site] }, payload[:duration])
    when "tracker.request"
      Yabeda.sherlock.tracker_requests_total.increment(payload.slice(:site, :status, :purpose, :key_owner))
      Yabeda.sherlock.tracker_request_duration_seconds.measure({ site: payload[:site] }, payload[:duration])
      Yabeda.sherlock.tracker_request_wait_seconds.measure({ site: payload[:site] }, payload[:wait])
    when "tracker.withheld"
      Yabeda.sherlock.tracker_requests_withheld_total.increment(payload.slice(:site, :reason, :purpose))
    end
  end
end.new)

# Polls run in the Solid Queue worker, a separate process from the web server (forked by Puma with
# SOLID_QUEUE_IN_PUMA, otherwise its own container), so the worker serves its own metrics on METRICS_PORT.
if Rails.env.production?
  require "rackup/handler/webrick"

  SolidQueue.on_start do
    Thread.new do
      Yabeda::Prometheus::Exporter.rack_handler.run(Yabeda::Prometheus::Exporter.rack_app,
        Host: ENV.fetch("METRICS_BIND", "0.0.0.0"), Port: ENV.fetch("METRICS_PORT", 9394).to_i, AccessLog: [])
    end
  end
end
