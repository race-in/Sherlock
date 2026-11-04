class Settings::AccountsController < ApplicationController
  def show
    @sessions = Current.user.sessions.order(updated_at: :desc)
  end

  def destroy
    if params[:username].to_s.strip.downcase == Current.user.username
      Current.user.destroy!
      cookies.delete(:session_id)
      reset_session
      redirect_to root_path, notice: "Your account and all its data are deleted.", status: :see_other
    else
      redirect_to settings_data_path, alert: "Type your username to confirm.", status: :see_other
    end
  end
end
