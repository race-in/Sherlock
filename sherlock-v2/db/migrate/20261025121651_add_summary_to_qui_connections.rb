# What the last full read found in this qui, on any tracker, for the settings page. Overwritten on every
# read, so there's no history. Null until all of the user's quis answered once.
class AddSummaryToQuiConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :qui_connections, :seeding, :integer
    add_column :qui_connections, :cross_seeded, :integer
    add_column :qui_connections, :cross_seeded_paused, :integer
    add_check_constraint :qui_connections, <<~SQL.squish, name: "qui_connections_summary_range"
      (seeding IS NULL AND cross_seeded IS NULL AND cross_seeded_paused IS NULL)
      OR (cross_seeded BETWEEN 0 AND seeding AND cross_seeded_paused >= 0)
    SQL
  end
end
