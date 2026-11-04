# Enforces the native install's one-account rule at the database boundary as well as
# the Rails model/controller boundary. The upstream multi-user test/development mode does not
# install this trigger; the bundled native installer sets SINGLE_USER_MODE=true before db:prepare.
class EnforceSingleUserMode < ActiveRecord::Migration[8.1]
  def up
    return unless Rails.application.config.x.single_user_mode

    execute <<~SQL
      CREATE FUNCTION sherlockdb.prevent_second_user()
      RETURNS trigger
      LANGUAGE plpgsql
      AS $function$
      BEGIN
        PERFORM pg_advisory_xact_lock(20481357, 1);
        IF EXISTS (SELECT 1 FROM sherlockdb.users) THEN
          RAISE EXCEPTION 'This Sherlock instance is configured for one account only.'
            USING ERRCODE = 'check_violation';
        END IF;
        RETURN NEW;
      END;
      $function$;

      CREATE TRIGGER users_single_user_guard
      BEFORE INSERT ON sherlockdb.users
      FOR EACH ROW
      EXECUTE FUNCTION sherlockdb.prevent_second_user();
    SQL
  end

  def down
    execute <<~SQL
      DROP TRIGGER IF EXISTS users_single_user_guard ON sherlockdb.users;
      DROP FUNCTION IF EXISTS sherlockdb.prevent_second_user();
    SQL
  end
end
