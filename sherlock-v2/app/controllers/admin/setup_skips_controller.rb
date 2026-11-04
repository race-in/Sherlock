# Marks an optional step of the admin's setup (AdminSetup) as done without doing it.
class Admin::SetupSkipsController < Admin::BaseController
  def create
    AdminSetup.new(Current.user).skip!(params.expect(:step))
    redirect_to dashboard_path
  rescue KeyError
    head :unprocessable_entity
  end
end
