# Step 1 of connecting a tracker that Sherlock reads with the instance key: the member's profile link.
# Nothing is sent to the tracker yet.
class Sites::ProfilesController < ApplicationController
  include ProfileClaims
  allow_unonboarded_access
  rate_limit to: 10, within: 1.minute, only: :create, with: -> { redirect_to new_site_connection_path(params[:site_slug]), alert: "Too many attempts. Wait a minute and try again." }
  before_action :set_site

  def create
    save_profile_claim ProfileClaim.start(params[:profile_url], sites: [ @site ], previous: profile_claim)
    redirect_to new_site_connection_path(@site)
  rescue ProfileClaim::Invalid => error
    redirect_to new_site_connection_path(@site), alert: error.message
  end

  def destroy
    forget_profile_claim
    redirect_to new_site_connection_path(@site), status: :see_other
  end

  private
    def set_site
      @site = Site.available_to(Current.user).instance_key.find_by!(slug: params[:site_slug])
    end
end
