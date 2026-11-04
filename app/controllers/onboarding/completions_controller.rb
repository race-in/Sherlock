class Onboarding::CompletionsController < ApplicationController
  allow_unonboarded_access
  layout "public"

  def show
    @connections = Current.user.connections.includes(:site).ordered
  end

  def create
    Current.user.complete_onboarding!
    redirect_to dashboard_path
  end
end
