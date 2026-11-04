# Torrents on the tracker whose files are also on another tracker, but where one of the two is paused,
# so they aren't counted as cross-seeded. Rows from before this column count as 0.
class AddCrossSeededPausedToCrossSeedSnapshots < ActiveRecord::Migration[8.1]
  def change
    add_column :cross_seed_snapshots, :cross_seeded_paused, :integer, null: false, default: 0
    add_check_constraint :cross_seed_snapshots, "cross_seeded_paused >= 0", name: "cross_seed_snapshots_paused_range"
  end
end
