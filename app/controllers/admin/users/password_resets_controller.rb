class Admin::Users::PasswordResetsController < Admin::Users::BaseController
  def create
    # Shown once in the flash and never stored in plain text.
    flash[:temporary_password] = @user.reset_password!
    redirect_to admin_user_path(@user)
  end
end
