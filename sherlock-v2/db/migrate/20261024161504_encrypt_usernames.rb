# Encrypts usernames at rest: the Sherlock username (deterministic, so sign in can still look it up
# and the unique index still holds) and the username and user id on each tracker. The format CHECK
# can't read ciphertext, so the model's validation is the only format check from here on.
class EncryptUsernames < ActiveRecord::Migration[8.1]
  class EncryptedUser < ActiveRecord::Base
    self.table_name = "users"
    encrypts :username, deterministic: true
  end

  class EncryptedConnection < ActiveRecord::Base
    self.table_name = "connections"
    encrypts :external_username, :external_user_id
  end

  COLUMNS = { EncryptedUser => %w[username], EncryptedConnection => %w[external_username external_user_id] }

  def up
    remove_check_constraint :users, name: "users_username_format"
    convert { |type, value| type.serialize(value) }
  end

  def down
    convert { |type, value| type.deserialize(value) }
    add_check_constraint :users, "username ~ '^[a-z0-9_.-]{2,32}$'", name: "users_username_format"
  end

  private
    # Raw SQL both ways. Going through the model would decrypt plaintext on read, or encrypt a
    # second time on write.
    def convert
      COLUMNS.each do |model, columns|
        select_rows("SELECT id, #{columns.join(", ")} FROM #{model.table_name}").each do |id, *values|
          sets = columns.zip(values).map { |column, value| "#{column} = #{quote(yield(model.type_for_attribute(column), value))}" }
          execute "UPDATE #{model.table_name} SET #{sets.join(", ")} WHERE id = #{Integer(id)}"
        end
      end
    end
end
