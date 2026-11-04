class Admin::UsersController < Admin::BaseController
  def index
    @users = User.order(:created_at).to_a
    @children = @users.group_by(&:invited_by_user_id)
    @connection_counts = Connection.group(:user_id).count
    @last_seen = Session.group(:user_id).maximum(:updated_at)
    @used_invites = Invite.counted.group(:created_by_user_id).count
    @query = params[:q].to_s.strip.downcase
    @match = @users.find { _1.username == @query } if @query.present?
    @signups = signups_per_day
  end

  def show
    @user = User.find(params[:id])
    @connections = @user.connections.includes(:site).ordered
    @granted_sites = Site.granted.where.not(tier: :unsupported).order(:name)
    @granted_site_ids = @user.site_grants.pluck(:site_id)
    @granted_integrations = Integration.granted.order(:name)
    @granted_integration_ids = @user.integration_grants.pluck(:integration_id)
  end

  def update
    @user = User.find(params[:id])
    @user.update!(params.expect(user: [ :invite_limit ]))
    redirect_to admin_user_path(@user), notice: "Invite limit set to #{@user.invite_limit}."
  end

  private
    # Days shown in the user charts, by range. All time starts on the day of the first account, and like
    # the rest shows at least 30 days.
    RANGES = { "month" => 30, "quarter" => 90, "year" => 365, "all" => nil }.freeze

    # New accounts on each day of the range, in the admin's time zone, with days without any as 0, and how
    # many there were before it. Deleted accounts are gone, so they count nowhere.
    def signups_per_day
      @range = params[:range].presence_in(RANGES) || "month"
      days = @users.map { _1.created_at.in_time_zone.to_date }
      first = [ Time.zone.today - (RANGES[@range] || RANGES["month"]) + 1, (days.min unless RANGES[@range]) ].compact.min
      counts = days.tally
      @users_before = days.count { _1 < first }
      (first..Time.zone.today).to_h { [ _1, counts.fetch(_1, 0) ] }
    end
end
