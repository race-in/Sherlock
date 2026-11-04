# Every request to a tracker takes a slot from its site first: at most one per request_interval, from all
# jobs and pages together. A site can also be paused, for a while or until someone acts, and then nothing
# is sent to it. failure_streak counts tracker-level errors (5xx, timeouts) in a row, across members.
class AddRequestGateToSites < ActiveRecord::Migration[8.1]
  def change
    create_enum :site_pause_reason, %w[rate_limited key_refused errors admin]

    add_column :sites, :request_interval, :interval, null: false, default: "PT2S"
    add_column :sites, :next_request_at, :datetime, null: false, default: -> { "now()" }
    add_column :sites, :pause_reason, :enum, enum_type: :site_pause_reason
    add_column :sites, :paused_until, :datetime
    add_column :sites, :failure_streak, :integer, null: false, default: 0

    add_check_constraint :sites, "request_interval >= interval '1 second'", name: "sites_request_interval_range"
    add_check_constraint :sites, "paused_until IS NULL OR pause_reason IS NOT NULL", name: "sites_paused_until_has_reason"
    add_check_constraint :sites, "failure_streak >= 0", name: "sites_failure_streak_range"
  end
end
