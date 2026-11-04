class Settings::Connections::PollsController < Settings::Connections::BaseController
  rate_limit to: 5, within: 1.minute, with: -> { redirect_back_or_to settings_connections_path, alert: "Too many tests. Wait a minute and try again." }

  def create
    if @connection.site.instance_key?
      return redirect_back_or_to settings_connection_path(@connection), notice: "Sherlock reads #{@connection.site.name} profiles once an hour."
    elsif @connection.recently_polled?
      return redirect_back_or_to settings_connection_path(@connection), notice: "#{@connection.site.name} was updated #{helpers.time_ago_in_words(@connection.polled_at)} ago. Try again later."
    end

    if @connection.poll!
      redirect_back_or_to settings_connection_path(@connection), notice: "#{@connection.site.display_name} answered. Numbers updated."
    else
      redirect_back_or_to settings_connection_path(@connection), alert: @connection.error_message
    end
  rescue Engines::Withheld => error
    redirect_back_or_to settings_connection_path(@connection), alert: error.message
  end
end
