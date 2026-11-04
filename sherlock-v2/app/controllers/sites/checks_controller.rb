# Step 2: reads the member's profile once and looks for their opt-in link.
class Sites::ChecksController < ApplicationController
  include ProfileClaims
  include TrackerQueue
  allow_unonboarded_access
  rate_limit to: 5, within: 1.minute, with: -> { redirect_to new_site_connection_path(params[:site_slug]), alert: "Too many checks. Wait a minute and try again." }
  before_action :set_site
  layout -> { Current.user.onboarded? ? "application" : "public" }

  def create
    claim = profile_claim
    return redirect_to new_site_connection_path(@site) unless claim&.site == @site

    check_profile_claim(claim) { redirect_to new_site_connection_path(@site) }
  end

  private
    def set_site
      @site = Site.available_to(Current.user).instance_key.find_by!(slug: params[:site_slug])
    end

    def render_profile_step
      render "sites/connections/new", status: :unprocessable_entity
    end
end
