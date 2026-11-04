# What qui saw for one tracker in one poll. Rows are only ever added; created_at is the poll time.
# Counts only torrents that are complete, seeding and announcing to the tracker without an error.
class CreateCrossSeedSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :cross_seed_snapshots do |t|
      t.references :connection, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.integer :torrents, null: false
      t.bigint :size, null: false
      # Upload as counted by the torrent client, not the tracker.
      t.bigint :uploaded, null: false
      # Of those, the torrents whose files also seed on another tracker.
      t.integer :cross_seeded, null: false
      t.bigint :cross_seeded_size, null: false
      t.bigint :cross_seeded_uploaded, null: false

      t.timestamps
    end
    add_index :cross_seed_snapshots, [ :connection_id, :created_at ]
    add_check_constraint :cross_seed_snapshots, <<~SQL.squish, name: "cross_seed_snapshots_range"
      torrents >= 0 AND size >= 0 AND uploaded >= 0
      AND cross_seeded BETWEEN 0 AND torrents AND cross_seeded_size BETWEEN 0 AND size
      AND cross_seeded_uploaded BETWEEN 0 AND uploaded
    SQL

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE TRIGGER set_updated_at_on_cross_seed_snapshots
          BEFORE UPDATE ON cross_seed_snapshots
          FOR EACH ROW EXECUTE FUNCTION set_updated_at();
        SQL
      end
    end
  end
end
