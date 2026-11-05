# Connects a tracker: with the member's own key, or on a site read with the instance key, with the
# profile they checked (Sites::ProfilesController, Sites::ChecksController).
class Sites::ConnectionsController < ApplicationController
  include TrackerQueue
  include ProfileClaims
  allow_unonboarded_access
  rate_limit to: 10, within: 1.minute, only: :create, with: -> { redirect_to new_site_connection_path(site_slug: params[:site_slug]), alert: "Too many tests. Wait a minute and try again." }
  before_action :set_site
  layout -> { Current.user.onboarded? ? "application" : "public" }

  def new
  end

  def create
    connection = @site.instance_key? ? connect_profile : Connection.connect!(user: Current.user, site: @site, api_key: @site.credential_from(params.expect(connection: [ :api_key, :username, :cookies ])))
    dequeue_tracker(@site.slug)
    redirect_to next_tracker_path, notice: "Connected to #{@site.display_name} as #{connection.external_username}."
  rescue Engines::Error => error
    @error = error
    render :new, status: :unprocessable_entity
  end

  private
    def set_site
      @site = Site.available_to(Current.user).find_by!(slug: params[:site_slug])
    end

    def connect_profile
      claim = profile_claim
      raise Engines::Error, "Check your profile again, then continue." unless claim&.site == @site && claim.ready?

      Connection.connect_profile!(user: Current.user, claim:).tap { forget_profile_claim }
    end
end
