# Step 2 of joining with an open invite: reads the profile once and looks for the opt-in link.
class Joins::ChecksController < ApplicationController
  include ProfileClaims
  allow_unauthenticated_access
  rate_limit to: 5, within: 1.minute, with: -> { redirect_to join_path(params[:code]), alert: "Too many checks. Wait a minute and try again." }
  before_action :set_invite
  layout "public"

  def create
    claim = profile_claim
    return redirect_to join_path(@invite) unless claim && @invite.joinable_sites.include?(claim.site)

    check_profile_claim(claim) { redirect_to join_path(@invite) }
  end

  private
    def set_invite
      @invite = Invite.usable.find_by!(code: params[:code])
    end

    def render_profile_step
      render "joins/show", status: :unprocessable_entity
    end
end
