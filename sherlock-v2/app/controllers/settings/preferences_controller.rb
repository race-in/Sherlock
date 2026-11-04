class Settings::PreferencesController < ApplicationController
  include PreferenceParams

  def edit
  end

  def update
    if Current.user.update(preference_params)
      redirect_to edit_settings_preferences_path, notice: "Preferences saved."
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
