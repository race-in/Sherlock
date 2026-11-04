class Admin::Users::BaseController < Admin::BaseController
  before_action :set_user

  private
    def set_user
      @user = User.find(params[:user_id])
    end
end
