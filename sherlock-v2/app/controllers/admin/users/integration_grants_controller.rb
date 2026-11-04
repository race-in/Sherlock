# Like GrantsController, for integrations such as qui.
class Admin::Users::IntegrationGrantsController < Admin::Users::BaseController
  def create
    integration = Integration.granted.find_by!(slug: params[:slug])
    @user.integration_grants.find_or_create_by!(integration:)
    redirect_to admin_user_path(@user), notice: "#{@user.username} can use #{integration.name} now."
  end

  def destroy
    integration = Integration.find_by!(slug: params[:slug])
    @user.integration_grants.where(integration:).delete_all
    redirect_to admin_user_path(@user), notice: "#{@user.username} can't use #{integration.name} anymore.", status: :see_other
  end
end
