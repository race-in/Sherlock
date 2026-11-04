class AddSnapshotProvenance < ActiveRecord::Migration[8.1]
  def change
    add_column :snapshots, :source, :string, default: "api", null: false
    add_column :snapshots, :note, :text
    add_column :snapshots, :created_by_user_id, :bigint
    add_column :snapshots, :import_batch_id, :string

    add_check_constraint :snapshots,
      "source IN ('api', 'manual', 'csv_import', 'json_import')",
      name: "snapshots_source_valid"
    add_check_constraint :snapshots,
      "note IS NULL OR char_length(note) <= 500",
      name: "snapshots_note_length"

    add_foreign_key :snapshots, :users, column: :created_by_user_id, on_delete: :nullify
  end
end
