class Settings::DataController < ApplicationController
  def show
    @connections = Current.user.connections.includes(:site).ordered
  end
end
