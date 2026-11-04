class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Too many attempts. Try again in a few minutes." }
  layout "public"

  def new
    redirect_to first_run_path if User.none?
  end

  def create
    user = User.authenticate_by(params.permit(:username, :password))
    if user && !user.is_disabled?
      url = after_authentication_url
      reset_session
      start_new_session_for user
      redirect_to url
    else
      redirect_to new_session_path, alert: "That username and password don't match."
    end
  end

  def destroy
    terminate_session
    redirect_to root_path, status: :see_other
  end
end
