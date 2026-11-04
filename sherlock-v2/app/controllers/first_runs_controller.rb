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
    unless valid_setup_token?
      @user.errors.add(:base, "The one-time installer token is missing or incorrect.")
      render :show, status: :unprocessable_entity
      return
    end
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
    def valid_setup_token?
      expected = ENV["FIRST_RUN_TOKEN"].to_s
      provided = params[:setup_token].to_s
      # Legacy development/test runs without a configured token keep their existing first-run flow.
      return true if expected.blank? && !Rails.application.config.x.single_user_mode

      expected.present? && provided.bytesize == expected.bytesize && ActiveSupport::SecurityUtils.secure_compare(expected, provided)
    end

    def require_no_users
      redirect_to root_path if User.exists?
    end
end
