class Admin::Users::DisablesController < Admin::Users::BaseController
  def create
    return redirect_to(admin_user_path(@user), alert: "You can't disable yourself.") if @user == Current.user

    @user.disable!
    redirect_to admin_user_path(@user), notice: "Disabled #{@user.username}. They're signed out and their trackers stop updating."
  end

  def destroy
    @user.enable!
    redirect_to admin_user_path(@user), notice: "Enabled #{@user.username}.", status: :see_other
  end
end
