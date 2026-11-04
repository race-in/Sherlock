class ConnectionsController < ApplicationController
  def show
    @connection = Current.user.connections.find(params[:id])
    @history = @connection.history(params[:range] || Current.user.default_range)
    @patterns = Patterns.new(@connection)
  end
end
