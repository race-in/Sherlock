class Connections::HistoriesController < ApplicationController
  ROWS_PER_PAGE = 50

  def show
    @connection = Current.user.connections.find(params[:connection_id])
    @history = @connection.history(params[:range] || Current.user.default_range)

    respond_to do |format|
      format.html do
        rows = @history.points.reverse
        @pages = [ rows.size.fdiv(ROWS_PER_PAGE).ceil, 1 ].max
        @page = params[:page].to_i.clamp(1, @pages)
        @rows = rows.slice((@page - 1) * ROWS_PER_PAGE, ROWS_PER_PAGE)
      end
      format.csv do
        send_data @history.to_csv, filename: "sherlock-#{@connection.site.slug}-#{@history.range}-#{Date.current}.csv", type: :csv
      end
    end
  end
end
