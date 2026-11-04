# Daily checks for a new Sherlock version (CheckForUpdateJob), off until the admin turns them on.
# The admin's setup gains a step for them. Instances that already exist skip it, so their dashboard
# doesn't go back to the setup for one optional step; Admin → Settings still has the switch.
class AddUpdateChecksToInstanceSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :instance_settings, :is_update_check_enabled, :boolean, null: false, default: false
    # The newest version tag Codeberg listed at the last check, like "v1.0.4".
    add_column :instance_settings, :latest_version, :text
    add_column :instance_settings, :update_checked_at, :datetime
    add_check_constraint :instance_settings, "char_length(latest_version) <= 100", name: "instance_settings_latest_version_length"

    remove_check_constraint :instance_settings, "skipped_setup_steps <@ ARRAY['invites']::text[]",
      name: "instance_settings_skipped_setup_steps_values"
    add_check_constraint :instance_settings, "skipped_setup_steps <@ ARRAY['invites', 'updates']::text[]",
      name: "instance_settings_skipped_setup_steps_values"

    reversible do |direction|
      direction.up { execute "UPDATE instance_settings SET skipped_setup_steps = array_append(skipped_setup_steps, 'updates')" }
      direction.down { execute "UPDATE instance_settings SET skipped_setup_steps = array_remove(skipped_setup_steps, 'updates')" }
    end
  end
end
