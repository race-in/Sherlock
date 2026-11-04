# Settings for the whole instance (InstanceSetting), as opposed to each tracker's in Admin → Sites.
class Admin::SettingsController < Admin::BaseController
  def show
    @setting = InstanceSetting.current
  end

  def update
    @setting = InstanceSetting.current
    attributes = params.expect(instance_setting: [ :tracker_contact, :is_update_check_enabled ])
    # Also saved from the setup on the dashboard, which it goes back to.
    if @setting.update(attributes)
      # The first check runs right away, so a newer version shows without waiting a day.
      CheckForUpdateJob.perform_later if @setting.is_update_check_enabled_previously_changed?(to: true)
      redirect_back_or_to admin_settings_path, notice: notice_for(attributes)
    else
      redirect_back_or_to admin_settings_path, alert: @setting.errors.full_messages.to_sentence
    end
  end

  private
    def notice_for(attributes)
      if attributes.key?(:is_update_check_enabled)
        @setting.is_update_check_enabled? ? "Update checks on." : "Update checks off."
      else
        @setting.tracker_contact ? "Contact saved." : "Contact removed."
      end
    end
end
