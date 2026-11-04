# Enforces the native install's one-account rule at the database boundary as well as
# the Rails model/controller boundary. The upstream multi-user test/development mode does not
# install this index; the bundled native installer sets SINGLE_USER_MODE=true before db:prepare.
class EnforceSingleUserMode < ActiveRecord::Migration[8.1]
  def up
    return unless Rails.application.config.x.single_user_mode

    # A constant-expression unique index is atomic under PostgreSQL concurrency and also rejects
    # multi-row INSERT statements; a row trigger that merely counts existing rows cannot guarantee
    # either property for rows created by the same statement.
    execute <<~SQL
      CREATE UNIQUE INDEX users_single_user_mode_idx
      ON sherlockdb.users ((true));
    SQL
  end

  def down
    execute "DROP INDEX IF EXISTS sherlockdb.users_single_user_mode_idx"
  end
end
