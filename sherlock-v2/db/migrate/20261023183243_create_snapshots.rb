class CreateSnapshots < ActiveRecord::Migration[8.1]
  def change
    # Rows are only ever added. created_at is the poll time. Every nullable stat is one some
    # trackers don't report: nil means "not reported", never 0.
    create_table :snapshots do |t|
      t.references :connection, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.bigint :uploaded, null: false
      t.bigint :downloaded, null: false
      t.decimal :ratio, precision: 12, scale: 4
      t.decimal :required_ratio, precision: 12, scale: 4
      t.decimal :bonus_points, precision: 16, scale: 2
      t.integer :seeding
      t.integer :leeching
      t.integer :snatched
      t.integer :hit_and_runs
      t.text :user_class

      t.timestamps
    end
    add_index :snapshots, [ :connection_id, :created_at ]
    add_check_constraint :snapshots, "uploaded >= 0 AND downloaded >= 0", name: "snapshots_bytes_range"
    add_check_constraint :snapshots, <<~SQL.squish, name: "snapshots_counts_range"
      COALESCE(seeding, 0) >= 0 AND COALESCE(leeching, 0) >= 0
      AND COALESCE(snatched, 0) >= 0 AND COALESCE(hit_and_runs, 0) >= 0
    SQL

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE TRIGGER set_updated_at_on_snapshots
          BEFORE UPDATE ON snapshots
          FOR EACH ROW EXECUTE FUNCTION set_updated_at();
        SQL
      end
    end
  end
end
