class Settings::OtherSessionsController < ApplicationController
  def destroy
    Current.user.sessions.where.not(id: Current.session.id).delete_all
    redirect_to settings_account_path, notice: "Signed out every other device.", status: :see_other
  end
end
