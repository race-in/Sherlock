# Closes a notice for good, such as the dashboard's first-day explanation (User#dismiss!).
class DismissalsController < ApplicationController
  def create
    Current.user.dismiss!(params.expect(:notice))
    redirect_back_or_to dashboard_path
  rescue KeyError
    head :unprocessable_entity
  end
end
