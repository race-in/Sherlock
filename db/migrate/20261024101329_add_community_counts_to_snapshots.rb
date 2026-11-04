class AddCommunityCountsToSnapshots < ActiveRecord::Migration[8.1]
  # Nullable like the other counts: NULL means the tracker doesn't report it.
  def change
    add_column :snapshots, :uploads, :integer
    add_column :snapshots, :forum_posts, :integer
    add_column :snapshots, :torrent_comments, :integer
    add_check_constraint :snapshots, "COALESCE(uploads, 0) >= 0 AND COALESCE(forum_posts, 0) >= 0 AND COALESCE(torrent_comments, 0) >= 0",
      name: "snapshots_community_counts_range"
  end
end
