# An invite for more than one person can be for one tracker's members, such as the forum it's posted in.
# Its profile step then shows that tracker, and its uses count who came from there. NULL lets in members of
# any tracker they can opt in on. A site with invites can't be deleted, so an invite never widens by itself.
class AddSiteToInvites < ActiveRecord::Migration[8.1]
  def change
    add_reference :invites, :site, foreign_key: { on_delete: :restrict }, index: true
    add_check_constraint :invites, "site_id IS NULL OR max_uses IS NULL OR max_uses > 1", name: "invites_site_only_when_open"
  end
end
