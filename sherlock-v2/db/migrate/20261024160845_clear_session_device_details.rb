# Sherlock no longer records the IP address or browser of a signed in device. This clears what was
# saved before. The columns are ignored by Session and get dropped in a later release.
class ClearSessionDeviceDetails < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE sessions SET ip_address = NULL, user_agent = NULL"
  end

  def down
  end
end
