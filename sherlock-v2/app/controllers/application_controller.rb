class ApplicationController < ActionController::Base
  include Authentication

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :require_password_change, :require_onboarding
  around_action :use_time_zone

  private
    def require_password_change
      redirect_to edit_password_path if Current.user&.is_password_change_required?
    end

    def require_onboarding
      redirect_to onboarding_welcome_path if Current.user && !Current.user.onboarded?
    end

    def use_time_zone(&)
      Time.use_zone(Current.user&.time_zone || "UTC", &)
    end

    def self.allow_unonboarded_access(**options)
      skip_before_action :require_onboarding, **options
    end
end
