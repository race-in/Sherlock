class DashboardsController < ApplicationController
  def show
    @connections = Current.user.connections.includes(:site).ordered.to_a
    @range = History.normalize_range(params[:range] || Current.user.default_range)
    @patterns = Patterns.new(@connections)
    @refreshing = refreshing?
  end

  private
    # From "Update all trackers now" until every tracker has answered, or two minutes at most. Each poll
    # morphs the page, so the spinner stops on the morph after the last one.
    def refreshing?
      requested = session[:refresh_requested_at]&.then { Time.zone.at(_1) }
      return false unless requested && requested > 2.minutes.ago

      @connections.any? { (_1.ok? || _1.failing?) && (_1.polled_at.nil? || _1.polled_at < requested) }
    end
end
