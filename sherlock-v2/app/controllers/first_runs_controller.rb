# Creates the first account, which is the admin, on a fresh install. Gone once any user exists.
class FirstRunsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_no_users
  layout "public"

  def show
    @user = User.new
  end

  def create
    @user = User.new(params.expect(user: %i[username password time_zone]).merge(is_admin: true))
    # Two requests at once would otherwise both pass require_no_users and make two admins.
    saved = User.transaction do
      User.connection.execute("LOCK TABLE users IN EXCLUSIVE MODE")
      User.none? && @user.save
    end
    if saved
      start_new_session_for @user
      redirect_to onboarding_welcome_path
    elsif @user.errors.any?
      render :show, status: :unprocessable_entity
    else
      redirect_to root_path
    end
  end

  private
    def require_no_users
      redirect_to root_path if User.exists?
    end
end
