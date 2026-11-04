# Reads a profile again after the member fixed what stopped it (Connection#needs_check?): put the opt-in
# link back, or showed uploaded and downloaded again.
class Settings::Connections::ChecksController < Settings::Connections::BaseController
  rate_limit to: 5, within: 1.minute, with: -> { redirect_to settings_connection_path(params[:connection_id]), alert: "Too many checks. Wait a minute and try again." }

  def create
    return redirect_to settings_connection_path(@connection) unless @connection.profile?

    if Current.set(tracker_purpose: "check") { @connection.poll! }
      redirect_to settings_connection_path(@connection), notice: "Found the link. Sherlock is tracking #{@connection.site.name} again."
    else
      redirect_to settings_connection_path(@connection), alert: @connection.error_message
    end
  rescue Engines::Withheld => error
    redirect_to settings_connection_path(@connection), alert: error.message
  end
end
