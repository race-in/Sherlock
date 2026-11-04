# Polls the user's trackers now instead of waiting for the hourly run. The jobs keep the usual per-site
# limits, and the open page refreshes itself as each poll finishes. Trackers asked in the last 15 minutes
# and profiles read with the instance key wait for their hourly poll.
class RefreshesController < ApplicationController
  rate_limit to: 5, within: 1.minute, with: -> { redirect_back_or_to dashboard_path, alert: "Too many refreshes. Wait a minute and try again." }

  def create
    connections = Current.user.connections.pollable.includes(:site).reject { _1.recently_polled? || _1.site.instance_key? }
    ActiveJob.perform_all_later(connections.map { PollConnectionJob.new(_1) })
    session[:refresh_requested_at] = Time.current.to_i if connections.any?
    redirect_back_or_to dashboard_path, notice: connections.any? ? "Updating #{helpers.pluralize(connections.size, "tracker")}." : "Your trackers are up to date."
  end
end
