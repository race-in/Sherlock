# Sets a tracker up like a self-hosted Sherlock would: the admin's key, tested, connects their own
# account. The one addition is `share`: people the admin invites can track their stats there too, by
# opting in on their profile where Sherlock can read profiles (Site#opt_in_possible?), or else with
# their own key. Used from Admin → Sites and the setup on the dashboard.
class Admin::Sites::SetupsController < Admin::Sites::BaseController
  rate_limit to: 5, within: 1.minute, only: :create, with: -> { redirect_to new_admin_site_setup_path(params[:site_slug]), alert: "Too many tests. Wait a minute and try again." }

  def new
  end

  def create
    return redirect_to dashboard_path, alert: "Add a contact for tracker staff first." if InstanceSetting.tracker_contact.blank?

    share? && @site.opt_in_possible? ? set_up_opt_in : set_up_with_own_keys
    redirect_to from_dashboard? ? dashboard_path : admin_site_path(@site),
      notice: share? ? "#{@site.name} is set up. People you invite can track their stats on it." : "#{@site.name} is set up for you."
  rescue Engines::Error => error
    flash[:setup_error] = error.message
    redirect_to from_dashboard? ? dashboard_path(setup_site: @site.slug, share: params[:share]) : new_admin_site_setup_path(@site, share: params[:share])
  end

  private
    def share?
      !Rails.application.config.x.single_user_mode && params[:share] == "1"
    end

    def from_dashboard?
      params[:from] == "dashboard"
    end

    def own_connection
      @own_connection ||= Current.user.connections.find_by(site: @site)
    end

    def api_key
      @site.credential_from(params.fetch(:connection, {}).permit(:api_key, :username))
    end

    # Site#use_instance_key! tests the key and reads the admin's own account with it, if it's on here.
    def set_up_opt_in
      @site.use_instance_key!(params.dig(:connection, :api_key))
      @site.update!(availability: :everyone)
      Connection.connect_key_owner!(user: Current.user, site: @site) unless own_connection
    end

    # The admin's key is tested first, so a refused key changes nothing. Leaving the admin's key for
    # everyone asks everyone on it for their own key, and the admin gives theirs right here.
    def set_up_with_own_keys
      key_owner = own_connection&.is_key_owner?
      raise Engines::Error, "Enter your #{@site.name} API key." if (own_connection.nil? || key_owner) && api_key.blank?

      stats = @site.adapter.fetch(api_key) unless own_connection
      Site.transaction do
        @site.use_member_keys! if @site.instance_key?
        @site.update_availability!(share? ? "everyone" : "granted")
        own_connection.reload.replace_key!(api_key) if key_owner
        Connection.connect!(user: Current.user, site: @site, api_key:, stats:) unless own_connection
      end
    end
end
