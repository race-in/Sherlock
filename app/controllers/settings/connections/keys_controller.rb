class Settings::Connections::KeysController < Settings::Connections::BaseController
  rate_limit to: 10, within: 1.minute, only: :update, with: -> { redirect_to settings_connection_path(params[:connection_id]), alert: "Too many tests. Wait a minute and try again." }

  def edit
  end

  def update
    @connection.replace_key!(@connection.site.credential_from(params.expect(connection: [ :api_key, :username, :cookies ])))
    redirect_to settings_connection_path(@connection), notice: "Key replaced. #{@connection.site.display_name} accepted it."
  rescue Engines::Error => error
    @error = error
    render :edit, status: :unprocessable_entity
  end
end
