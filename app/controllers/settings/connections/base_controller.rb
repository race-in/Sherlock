class Settings::Connections::BaseController < ApplicationController
  before_action :set_connection

  private
    def set_connection
      @connection = Current.user.connections.find(params[:connection_id])
    end
end
