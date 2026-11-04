# An admin's invite can let more than one person join, and can last forever. So the link turns around:
# each user points at the invite they used, invites count their uses, and invites.used_by_user_id and
# used_at go. uses never goes down, so deleting an account doesn't hand its invite out again. Nothing runs
# in production yet, so the old columns go in the same release, but self-hosted instances keep their
# data: the backfill runs before the drop.
class MakeInvitesReusable < ActiveRecord::Migration[8.1]
  def up
    add_reference :users, :invite, foreign_key: { on_delete: :nullify }, index: true
    execute "UPDATE users u SET invite_id = i.id FROM invites i WHERE i.used_by_user_id = u.id"
    add_column :invites, :uses, :integer, null: false, default: 0
    execute "UPDATE invites SET uses = 1 WHERE used_at IS NOT NULL"

    remove_check_constraint :invites, name: "invites_used_at_set_when_used"
    remove_check_constraint :invites, name: "invites_used_or_revoked"
    remove_reference :invites, :used_by_user, foreign_key: { to_table: :users }, index: { unique: true }
    remove_column :invites, :used_at

    add_column :invites, :max_uses, :integer, default: 1
    add_check_constraint :invites, "max_uses IS NULL OR max_uses >= 1", name: "invites_max_uses_range"
    add_check_constraint :invites, "uses >= 0 AND (max_uses IS NULL OR uses <= max_uses)", name: "invites_uses_range"
    change_column_null :invites, :expires_at, true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
