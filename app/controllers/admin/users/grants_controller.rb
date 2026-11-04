# Lets one person use a tracker that's only for granted people, or takes that back. Taking it back
# stops the tracker updating for them, but keeps their key and history.
class Admin::Users::GrantsController < Admin::Users::BaseController
  def create
    site = Site.granted.find_by!(slug: params[:slug])
    @user.site_grants.find_or_create_by!(site:)
    redirect_to admin_user_path(@user), notice: "#{@user.username} can use #{site.display_name} now."
  end

  def destroy
    site = Site.find_by!(slug: params[:slug])
    @user.site_grants.where(site:).delete_all
    redirect_to admin_user_path(@user), notice: "#{@user.username} can't use #{site.display_name} anymore.", status: :see_other
  end
end
