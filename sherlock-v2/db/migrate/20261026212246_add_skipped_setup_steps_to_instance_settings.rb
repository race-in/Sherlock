# Optional admin setup steps (AdminSetup) the admin chose to skip. Only optional steps can be skipped.
class AddSkippedSetupStepsToInstanceSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :instance_settings, :skipped_setup_steps, :text, array: true, null: false, default: []
    add_check_constraint :instance_settings, "skipped_setup_steps <@ ARRAY['invites']::text[]",
      name: "instance_settings_skipped_setup_steps_values"
  end
end
