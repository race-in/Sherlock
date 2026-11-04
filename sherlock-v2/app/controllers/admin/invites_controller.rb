class Admin::InvitesController < Admin::BaseController
  EXPIRES = { "14" => 14.days, "30" => 30.days, "never" => nil }.freeze

  def index
    @invites = Invite.includes(:created_by_user, :site).newest_first
    @joinable_sites = Site.joinable.to_a
  end

  def create
    invite = Current.user.created_invites.create(invite_params)
    if invite.persisted?
      # Also created from the setup on the dashboard, which shows the new link.
      redirect_back_or_to admin_invites_path, notice: "Invite created.", flash: { invite_code: invite.code }
    else
      redirect_back_or_to admin_invites_path, alert: invite.errors.full_messages.to_sentence
    end
  end

  def destroy
    Invite.find_by!(code: params[:code]).revoke!
    redirect_to admin_invites_path, notice: "Invite revoked.", status: :see_other
  end

  private
    def invite_params
      choice = params.expect(invite: %i[uses max_uses expires site_id])
      max_uses = case choice[:uses]
      when "limit" then choice[:max_uses].to_i
      when "unlimited" then nil
      else 1
      end
      site_id = Site.joinable.find_by(id: choice[:site_id])&.id if max_uses != 1
      { max_uses:, site_id:, expires_at: EXPIRES.fetch(choice[:expires], Invite::TTL)&.from_now }
    end
end
