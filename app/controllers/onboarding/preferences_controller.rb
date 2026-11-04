class Onboarding::PreferencesController < ApplicationController
  include PreferenceParams
  allow_unonboarded_access
  layout "public"

  def show
  end

  def update
    if Current.user.update(preference_params)
      # The admin adds trackers from the setup on the dashboard, after the contact for tracker staff
      # that every request carries (AdminSetup).
      if Current.user.is_admin?
        Current.user.complete_onboarding!
        redirect_to dashboard_path
      elsif Current.user.connections.exists?
        # Joined through a tracker profile, so that tracker is already connected.
        redirect_to onboarding_completion_path
      else
        redirect_to tracker_selection_path
      end
    else
      render :show, status: :unprocessable_entity
    end
  end
end
