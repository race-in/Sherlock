class ComparisonsController < ApplicationController
  def show
    @connections = Current.user.connections.includes(:site).ordered.to_a
    @stat = PinnedComparison::STATS.key?(params[:stat]) ? params[:stat] : "buffer"
    @range = History.normalize_range(params[:range] || Current.user.default_range)
    @per_interval = params[:mode] == "interval"
    selected = Array(params[:ids]).map(&:to_i)
    @selected = selected.any? ? @connections.select { selected.include?(_1.id) } : @connections
    @pins = Current.user.pinned_comparisons.chronological.includes(:user)
    @pin = @pins.find { _1.stat == @stat && _1.range == @range && _1.is_per_interval? == @per_interval && _1.connection_ids == @selected.map(&:id).sort }
  end
end
