class Comparisons::PinsController < ApplicationController
  def create
    stat = params[:stat].presence_in(PinnedComparison.stats.keys)
    range = params[:range].presence_in(PinnedComparison.ranges.keys)
    ids = Current.user.connections.where(id: Array(params[:ids]).presence || Current.user.connections.select(:id)).ids
    if stat && range && ids.any?
      pin = Current.user.pinned_comparisons.pin!(stat:, range:, is_per_interval: params[:mode] == "interval", connection_ids: ids)
      redirect_to comparison_path(pin.compare_params), notice: "Chart pinned."
    else
      redirect_to comparison_path, alert: "This chart can't be pinned."
    end
  end

  def destroy
    pin = Current.user.pinned_comparisons.find(params[:id])
    pin.destroy!
    redirect_to comparison_path(pin.compare_params), notice: "Chart unpinned.", status: :see_other
  end
end
