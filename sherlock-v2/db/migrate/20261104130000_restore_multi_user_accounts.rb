# Remove the single-user-only index introduced by an earlier Custom Edition build.
# This is safe for fresh installs and restores invite-based multi-user accounts on upgraded DBs.
class RestoreMultiUserAccounts < ActiveRecord::Migration[8.1]
  def up
    execute "DROP INDEX IF EXISTS sherlockdb.users_single_user_mode_idx"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Re-enabling a single-user-only index can fail when multiple accounts already exist."
  end
end
