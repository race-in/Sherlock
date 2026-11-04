class Settings::TrackerOrdersController < ApplicationController
  # Sent by the sortable controller after each drag, with every tracker's id in the new order.
  def update
    Connection.reorder!(Current.user, Array(params[:ids]))
    head :no_content
  end
end
