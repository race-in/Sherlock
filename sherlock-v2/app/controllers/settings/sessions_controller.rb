class Settings::SessionsController < ApplicationController
  def destroy
    Current.user.sessions.where.not(id: Current.session.id).find(params[:id]).destroy!
    redirect_to settings_account_path, notice: "Signed out that device.", status: :see_other
  end
end
