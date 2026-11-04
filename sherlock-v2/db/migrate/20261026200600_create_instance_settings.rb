# Settings for the whole instance, one row. The first is how tracker staff reach the person running it,
# sent with every tracker request.
class CreateInstanceSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :instance_settings do |t|
      t.text :tracker_contact

      t.timestamps
    end
    add_check_constraint :instance_settings, "char_length(tracker_contact) <= 200", name: "instance_settings_tracker_contact_length"
    add_index :instance_settings, "(true)", unique: true, name: "index_instance_settings_single_row"

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE TRIGGER set_updated_at_on_instance_settings
          BEFORE UPDATE ON instance_settings
          FOR EACH ROW EXECUTE FUNCTION set_updated_at();
        SQL
      end
    end
  end
end
