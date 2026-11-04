class Onboarding::WelcomesController < ApplicationController
  allow_unonboarded_access
  layout "public"

  def show
  end

  def update
    # Members who joined through a tracker profile never give Sherlock a key, so there are no rules to accept.
    if params[:accept] == "1" || Current.user.connections.exists?
      Current.user.update!(tracker_rules_accepted_at: Time.current)
      redirect_to onboarding_preferences_path
    else
      flash.now[:alert] = "Tick the box to continue."
      render :show, status: :unprocessable_entity
    end
  end
end
