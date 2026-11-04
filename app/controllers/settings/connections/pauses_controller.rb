class Settings::Connections::PausesController < Settings::Connections::BaseController
  def create
    @connection.pause!
    redirect_back_or_to settings_connection_path(@connection), notice: "Paused #{@connection.site.display_name}. Sherlock won't update it until you resume."
  end

  def destroy
    @connection.resume!
    redirect_back_or_to settings_connection_path(@connection), notice: "Resumed #{@connection.site.display_name}.", status: :see_other
  end
end
