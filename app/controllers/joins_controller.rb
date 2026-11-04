# Signing up with an invite. A personal invite asks for a username and password. An open invite first
# has the new member prove a tracker profile that Sherlock reads with the instance key (Joins::ProfilesController,
# Joins::ChecksController), and saves it together with the account.
class JoinsController < ApplicationController
  include ProfileClaims
  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_join_path, alert: "Too many attempts. Try again in a few minutes." }
  before_action :redirect_signed_in
  before_action :set_invite, only: %i[show create]
  layout "public"

  def new
    redirect_to join_path(params[:code].strip) if params[:code].present?
  end

  def show
  end

  def create
    user = @invite.accept!(**params.expect(user: %i[username password time_zone]).to_h.symbolize_keys, claim: profile_claim)
    forget_profile_claim
    start_new_session_for user
    redirect_to onboarding_welcome_path
  rescue ActiveRecord::RecordInvalid => error
    @user = error.record
    render :show, status: :unprocessable_entity
  rescue Engines::Error => error
    @error = error
    render :show, status: :unprocessable_entity
  rescue Invite::Unusable
    redirect_to new_join_path, alert: "This invite can't be used any more."
  end

  private
    def redirect_signed_in
      redirect_to dashboard_path if authenticated?
    end

    def set_invite
      @invite = Invite.usable.find_by(code: params[:code])
      redirect_to new_join_path, alert: "That invite code doesn't work. It may be used, expired or revoked." unless @invite
    end
end
