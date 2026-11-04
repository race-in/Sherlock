class Settings::MetricsTokensController < ApplicationController
  # Rendered, not redirected, so the token never lands in the session cookie or a URL. The form
  # skips Turbo for the same reason.
  def create
    @token = Current.user.regenerate_metrics_token!
    render "settings/developer/show"
  end

  def destroy
    Current.user.revoke_metrics_token!
    redirect_to settings_developer_path, notice: "Token revoked. Scrapes with it now fail.", status: :see_other
  end
end
