# What buffer means for a user: uploaded minus downloaded (ratio 1.0), or what they can still
# download before falling below the tracker's required ratio.
class AddBufferBasisToUsers < ActiveRecord::Migration[8.1]
  def up
    execute "CREATE TYPE buffer_basis AS ENUM ('one_to_one', 'required_ratio')"
    add_column :users, :buffer_basis, :buffer_basis, null: false, default: "one_to_one"
  end

  def down
    remove_column :users, :buffer_basis
    execute "DROP TYPE buffer_basis"
  end
end
