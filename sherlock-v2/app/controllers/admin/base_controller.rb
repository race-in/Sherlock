# Also the base for Mission Control Jobs at /jobs (config/application.rb).
class Admin::BaseController < ApplicationController
  before_action :require_admin

  private
    def require_admin
      head :not_found unless Current.user&.is_admin?
    end
end
