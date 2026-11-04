# Step 1 of joining with an open invite: the new member's profile link. Nothing is sent to the tracker.
class Joins::ProfilesController < ApplicationController
  include ProfileClaims
  allow_unauthenticated_access
  rate_limit to: 10, within: 1.minute, only: :create, with: -> { redirect_to join_path(params[:code]), alert: "Too many attempts. Wait a minute and try again." }
  before_action :set_invite

  def create
    save_profile_claim ProfileClaim.start(params[:profile_url], sites: @invite.joinable_sites.to_a, previous: profile_claim)
    redirect_to join_path(@invite)
  rescue ProfileClaim::Invalid => error
    redirect_to join_path(@invite), alert: error.message
  end

  def destroy
    forget_profile_claim
    redirect_to join_path(@invite), status: :see_other
  end

  private
    def set_invite
      @invite = Invite.usable.find_by!(code: params[:code])
    end
end
