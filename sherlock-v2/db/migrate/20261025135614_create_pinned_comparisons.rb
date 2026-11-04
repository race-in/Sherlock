# A chart from the compare page that the user pinned, so it's there whenever they come back.
class CreatePinnedComparisons < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      CREATE TYPE comparison_stat AS ENUM (
        'buffer', 'uploaded', 'downloaded', 'ratio', 'interval_ratio', 'seeding', 'leeching',
        'snatched', 'uploads', 'forum_posts', 'torrent_comments'
      );
    SQL

    create_table :pinned_comparisons do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.column :stat, :comparison_stat, null: false
      t.column :range, :chart_range, null: false
      t.boolean :is_per_interval, null: false, default: false
      # No foreign key per element: a removed tracker just drops out of the chart.
      t.bigint :connection_ids, array: true, null: false

      t.timestamps
    end
    add_index :pinned_comparisons, %i[user_id stat range is_per_interval connection_ids], unique: true,
      name: "index_pinned_comparisons_uniquely"
    add_check_constraint :pinned_comparisons, "cardinality(connection_ids) > 0", name: "pinned_comparisons_connection_ids_present"

    execute <<~SQL
      CREATE TRIGGER set_updated_at_on_pinned_comparisons
      BEFORE UPDATE ON pinned_comparisons
      FOR EACH ROW EXECUTE FUNCTION set_updated_at();
    SQL
  end

  def down
    drop_table :pinned_comparisons
    execute "DROP TYPE comparison_stat"
  end
end
