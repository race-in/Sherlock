class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_enum :byte_unit, %w[iec si]
    create_enum :chart_range, %w[day week month quarter year all]
    create_enum :theme, %w[system light dark]

    create_table :users do |t|
      t.text :username, null: false
      t.text :password_digest, null: false
      # Null only for the first admin, created on /first_run, who has no inviter.
      t.references :invited_by_user, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :invite_limit, null: false, default: 3
      t.boolean :is_admin, null: false, default: false
      t.boolean :is_disabled, null: false, default: false
      t.boolean :is_password_change_required, null: false, default: false
      t.text :time_zone, null: false, default: "UTC"
      t.enum :byte_unit, enum_type: :byte_unit, null: false, default: "iec"
      t.enum :default_range, enum_type: :chart_range, null: false, default: "week"
      t.enum :theme, enum_type: :theme, null: false, default: "system"
      t.boolean :is_chart_filled, null: false, default: true
      t.boolean :is_chart_points_shown, null: false, default: false
      # Null until the user ticks the tracker rules note in onboarding.
      t.datetime :tracker_rules_accepted_at
      # Null while onboarding still runs.
      t.datetime :onboarding_completed_at

      t.timestamps
    end
    add_index :users, :username, unique: true
    add_check_constraint :users, "username ~ '^[a-z0-9_.-]{2,32}$'", name: "users_username_format"
    add_check_constraint :users, "invite_limit >= 0", name: "users_invite_limit_range"

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE TRIGGER set_updated_at_on_users
          BEFORE UPDATE ON users
          FOR EACH ROW EXECUTE FUNCTION set_updated_at();
        SQL
      end
    end
  end
end
