class Settings::ConnectionsController < ApplicationController
  def index
    @connections = Current.user.connections.includes(:site).ordered
  end

  def show
    @connection = Current.user.connections.find(params[:id])
  end

  def destroy
    connection = Current.user.connections.find(params[:id])
    connection.destroy!
    redirect_to settings_connections_path, notice: "Removed #{connection.site.display_name} and its history.", status: :see_other
  end
end
