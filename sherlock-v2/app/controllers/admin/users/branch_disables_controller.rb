class Admin::Users::BranchDisablesController < Admin::Users::BaseController
  def create
    return redirect_to(admin_user_path(@user), alert: "That branch includes you.") if User.branch_ids(@user.id).include?(Current.user.id)

    count = @user.disable_branch!
    redirect_to admin_user_path(@user), notice: "Disabled #{count} #{"user".pluralize(count)}: #{@user.username} and everyone they invited."
  end
end
