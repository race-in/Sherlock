class Settings::Connections::ColorsController < Settings::Connections::BaseController
  def update
    if @connection.update(color:)
      redirect_to settings_connection_path(@connection), notice: "Color saved."
    else
      redirect_to settings_connection_path(@connection), alert: @connection.errors.full_messages.to_sentence
    end
  end

  private
    def color
      params.expect(connection: [ :color ])[:color].presence
    end
end
