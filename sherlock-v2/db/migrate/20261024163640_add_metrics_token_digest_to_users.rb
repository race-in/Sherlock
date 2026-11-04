# A SHA-256 of the user's Prometheus token. NULL means the user's metrics endpoint is off.
class AddMetricsTokenDigestToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :metrics_token_digest, :text
    add_index :users, :metrics_token_digest, unique: true
  end
end
