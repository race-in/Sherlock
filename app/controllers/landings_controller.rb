class LandingsController < ApplicationController
  allow_unauthenticated_access
  layout "public"

  def show
    if authenticated?
      redirect_to dashboard_path
    elsif User.none?
      redirect_to first_run_path
    end
  end
end
