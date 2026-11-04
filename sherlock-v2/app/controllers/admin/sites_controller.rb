class Admin::SitesController < Admin::BaseController
  AVAILABILITY = { "everyone" => "Everyone", "granted" => "Granted only", "off" => "Off" }.freeze

  before_action :set_site, only: %i[show update]

  def index
    @sites = Site.where.not(tier: :unsupported).order(:name)
    @status_counts = Connection.group(:site_id, :status).count
    @connection_counts = Connection.group(:site_id).count
    @grant_counts = SiteGrant.group(:site_id).count
    @integrations = Integration.order(:name)
    @connected_counts = { "qui" => QuiConnection.distinct.count(:user_id) }
    @integration_grant_counts = IntegrationGrant.group(:integration_id).count
  end

  def show
    @key_count = @site.connections.where.not(credential: nil).count
    @granted_users = User.where(id: @site.site_grants.select(:user_id)).order(:username)
    @member_count = @site.connections.where.not(user: Current.user).count
  end

  # Turning a site off deletes the keys members saved for it, so that asks first (see show).
  def update
    changes = params.expect(site: %i[availability request_interval])
    if changes[:request_interval]
      @site.update!(request_interval: changes[:request_interval].to_i.clamp(1, 3600).seconds)
      redirect_to admin_site_path(@site), notice: "#{@site.name}: one request every #{helpers.pluralize(@site.request_interval.to_i, "second")}."
    elsif changes[:availability] == "off" && !params[:confirmed] && @site.connections.where.not(credential: nil).exists?
      redirect_to admin_site_path(@site, confirm: "off")
    else
      @site.update_availability!(changes[:availability])
      redirect_back_or_to admin_sites_path, notice: "#{@site.name}: #{AVAILABILITY.fetch(@site.availability).downcase}."
    end
  end

  private
    def set_site
      @site = Site.where.not(tier: :unsupported).find_by!(slug: params[:slug])
    end
end
