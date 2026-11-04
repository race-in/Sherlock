class PasswordsController < ApplicationController
  skip_before_action :require_password_change, :require_onboarding

  def edit
    render layout: "public" if Current.user.is_password_change_required?
  end

  def update
    if Current.user.change_password!(**params.expect(user: %i[password password_confirmation password_challenge]).to_h.symbolize_keys)
      Current.user.sessions.where.not(id: Current.session.id).delete_all
      redirect_to Current.user.onboarded? ? settings_account_path : onboarding_welcome_path, notice: "Password changed. Other devices were signed out."
    else
      render :edit, status: :unprocessable_entity, layout: Current.user.is_password_change_required? ? "public" : "application"
    end
  end
end
