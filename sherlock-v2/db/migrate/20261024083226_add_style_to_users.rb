class AddStyleToUsers < ActiveRecord::Migration[8.1]
  def change
    create_enum :ui_style, %w[v2 classic]
    add_column :users, :style, :enum, enum_type: :ui_style, null: false, default: "v2"
  end
end
