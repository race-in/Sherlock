class TrackerSelectionsController < ApplicationController
  include TrackerQueue
  allow_unonboarded_access
  layout -> { Current.user.onboarded? ? "application" : "public" }
  before_action :require_tracker_contact


  def show
    @connected_site_ids = Current.user.connections.pluck(:site_id)
    @sites = Site.available_to(Current.user)
  end

  def update
    slugs = Site.available_to(Current.user).where(slug: Array(params[:slugs])).where.not(id: Current.user.connections.select(:site_id)).order(:name).pluck(:slug)
    queue_trackers(slugs)
    redirect_to next_tracker_path
  end

  private
    # The admin's first request to a tracker already carries the contact for its staff (AdminSetup).
    def require_tracker_contact
      if Current.user.is_admin? && InstanceSetting.tracker_contact.blank?
        redirect_to dashboard_path, alert: "Add a contact for tracker staff first."
      end
    end
end
