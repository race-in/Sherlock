class Settings::InvitesController < ApplicationController
  def index
    @invites = Current.user.created_invites.includes(:users).newest_first
  end

  def create
    # The lock makes parallel requests count one after another, so nobody gets past their invite limit.
    invite = Current.user.with_lock { Current.user.created_invites.create! if Current.user.can_invite? }
    if invite
      redirect_to settings_invites_path, notice: "Invite created. It works once and expires on #{invite.expires_at.to_date.to_fs(:long)}."
    else
      redirect_to settings_invites_path, alert: "You have no invites left."
    end
  end

  def destroy
    Current.user.created_invites.find_by!(code: params[:code]).revoke!
    redirect_to settings_invites_path, notice: "Invite revoked.", status: :see_other
  end
end
