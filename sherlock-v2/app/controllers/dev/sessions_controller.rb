# Development only (see config/routes.rb). Signs in the seeded dev admin so nobody types a password
# while working locally.
class Dev::SessionsController < ApplicationController
  allow_unauthenticated_access

  def show
    start_new_session_for User.find_by!(username: params.fetch(:username, "dev"))
    return_to = params[:return_to].to_s
    redirect_to return_to.match?(%r{\A/(?![/\\])}) ? return_to : dashboard_path
  end
end
