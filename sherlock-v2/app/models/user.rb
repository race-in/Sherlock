class User < ApplicationRecord
  has_secure_password

  has_many :sessions, dependent: :delete_all
  has_many :connections
  has_many :snapshots, through: :connections
  has_many :qui_connections
  has_many :pinned_comparisons
  has_many :site_grants
  has_many :integration_grants
  has_many :created_invites, class_name: "Invite", foreign_key: :created_by_user_id, inverse_of: :created_by_user
  belongs_to :invite, optional: true, inverse_of: :users
  belongs_to :invited_by_user, class_name: "User", optional: true
  has_many :invitees, class_name: "User", foreign_key: :invited_by_user_id, inverse_of: :invited_by_user

  enum :byte_unit, { iec: "iec", si: "si" }, prefix: true
  enum :default_range, { day: "day", week: "week", month: "month", quarter: "quarter", year: "year", all: "all" }, prefix: true
  enum :theme, { system: "system", light: "light", dark: "dark" }, prefix: true
  enum :buffer_basis, { one_to_one: "one_to_one", required_ratio: "required_ratio" }, prefix: true

  normalizes :username, with: ->(username) { username.strip.downcase }
  # Deterministic, so sign in can find a user by username and the unique index still works.
  # It also means the database can't sort by username: sort in Ruby.
  encrypts :username, deterministic: true

  validates :username, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9_.-]{2,32}\z/, message: "can use 2 to 32 letters, numbers, dots, dashes and underscores" }
  validates :password, length: { minimum: 10, maximum: 72 }, allow_nil: true
  validates :time_zone, inclusion: { in: ->(_) { TZInfo::Timezone.all_identifiers }, message: "isn't a time zone we know" }
  validates :invite_limit, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :enforce_single_user_mode, on: :create

  scope :enabled, -> { where(is_disabled: false) }

  # Serializes every app-level account creation before checking the one-account invariant.
  # The lock and existence check run inside the save transaction, so concurrent Rails requests cannot
  # both observe an empty users table and create a second account.
  def enforce_single_user_mode
    return unless Rails.application.config.x.single_user_mode

    self.class.connection.execute("LOCK TABLE users IN EXCLUSIVE MODE")
    errors.add(:base, "This Sherlock instance is configured for one account only.") if self.class.exists?
  end

  # Users are polled at different points in the hour so trackers never see everyone at once. A user
  # keeps the same slot, so their trackers update together. Multiplying by the golden ratio spreads
  # consecutive ids evenly across the hour.
  def poll_offset
    (id * 0.6180339887 % 1 * 1.hour.to_i).floor.seconds
  end

  def next_poll_at(now = Time.current)
    at = now.beginning_of_hour + poll_offset
    at > now ? at : at + 1.hour
  end

  # The user and everyone they invited, and everyone those people invited, and so on.
  def self.branch_ids(root_id)
    connection.select_values(sanitize_sql([ <<~SQL, root_id ])).map(&:to_i)
      WITH RECURSIVE branch(id) AS (
        SELECT u.id FROM users u WHERE u.id = ?
        UNION
        SELECT u.id FROM users u JOIN branch b ON (u.invited_by_user_id = b.id)
      )
      SELECT b.id FROM branch b
    SQL
  end

  # Only a digest is stored, so a token is shown once, when it's made. Replacing it stops the old one.
  def regenerate_metrics_token!
    "sherlock_#{SecureRandom.base58(32)}".tap { update!(metrics_token_digest: self.class.metrics_token_digest(_1)) }
  end

  def revoke_metrics_token!
    update!(metrics_token_digest: nil)
  end

  def self.find_by_metrics_token(token)
    enabled.find_by(metrics_token_digest: metrics_token_digest(token)) if token.present?
  end

  def self.metrics_token_digest(token)
    Digest::SHA256.hexdigest(token)
  end

  def onboarded?
    onboarding_completed_at.present?
  end

  def complete_onboarding!
    update!(onboarding_completed_at: Time.current) unless onboarded?
  end

  # Notices a user can close for good, kept in ui_state["dismissed"]. The update notice is closed for
  # one version, so it comes back for the next.
  DISMISSIBLE = %w[first_numbers update].freeze

  def dismissed?(notice)
    ui_state.dig("dismissed", notice).present?
  end

  def dismiss!(notice)
    raise KeyError, notice unless DISMISSIBLE.include?(notice)

    value = notice == "update" ? InstanceSetting.current.available_update : Time.current.iso8601
    update!(ui_state: ui_state.deep_merge("dismissed" => { notice => value }))
  end

  # The newer version to tell this user about, for admins only, until they close the notice for it.
  def update_notice
    return unless is_admin?

    version = InstanceSetting.current.available_update
    version unless version.nil? || ui_state.dig("dismissed", "update") == version
  end

  def invites_left
    [ invite_limit - created_invites.counted.count, 0 ].max
  end

  def can_invite?
    is_admin? || invites_left.positive?
  end

  def reset_password!
    password = SecureRandom.alphanumeric(16)
    transaction do
      update!(password:, is_password_change_required: true)
      sessions.delete_all
    end
    password
  end

  # Rails only checks a challenge that isn't nil, so a missing one becomes "" and fails.
  def change_password!(password:, password_confirmation:, password_challenge:)
    update(password:, password_confirmation:, password_challenge: password_challenge.to_s, is_password_change_required: false)
  end

  def disable!
    transaction do
      update!(is_disabled: true)
      sessions.delete_all
    end
  end

  def enable!
    update!(is_disabled: false)
  end

  def disable_branch!
    ids = self.class.branch_ids(id)
    transaction do
      self.class.where(id: ids).update_all(is_disabled: true)
      Session.where(user_id: ids).delete_all
    end
    ids.size
  end

  def branch
    self.class.where(id: self.class.branch_ids(id)).where.not(id:).sort_by(&:username)
  end

  # Everything Sherlock stores about the user, minus secrets: no password digest, no API keys.
  def export
    {
      exported_at: Time.current,
      user: slice(:username, :time_zone, :byte_unit, :default_range, :theme, :is_chart_filled, :is_chart_points_shown, :is_tracker_name_short, :buffer_basis, :created_at)
        .merge(invited_by: invited_by_user&.username),
      invites: created_invites.includes(:users).map { { status: _1.status, max_uses: _1.max_uses, used_by: _1.users.map(&:username), created_at: _1.created_at, expires_at: _1.expires_at } },
      trackers: connections.includes(:site).map do |connection|
        connection.slice(:external_username, :status, :created_at).merge(
          site: connection.site.name,
          snapshots: connection.snapshots.chronological.map { _1.slice(:created_at, *IMPORT_COLUMNS) },
          cross_seeds: connection.cross_seed_snapshots.chronological.map { _1.slice(:created_at, *CROSS_SEED_IMPORT_COLUMNS) }
        )
      end,
      pinned_charts: pinned_comparisons.chronological.map do |pin|
        pin.slice(:stat, :range, :is_per_interval, :created_at).merge(trackers: pin.connections.map { _1.site.name })
      end
    }
  end

  METRICS = {
    uploaded: [ "uploaded_bytes", "Uploaded, as the tracker last reported it" ],
    downloaded: [ "downloaded_bytes", "Downloaded, as the tracker last reported it" ],
    buffer: [ "buffer_bytes", "Uploaded minus downloaded" ],
    ratio: [ "ratio", "Ratio" ],
    required_ratio: [ "required_ratio", "Required ratio" ],
    bonus_points: [ "bonus_points", "Bonus points" ],
    seeding: [ "seeding", "Torrents seeding" ],
    leeching: [ "leeching", "Torrents leeching" ],
    snatched: [ "snatched", "Torrents snatched" ],
    hit_and_runs: [ "hit_and_runs", "Hit and runs" ],
    uploads: [ "uploads", "Torrents uploaded" ],
    forum_posts: [ "forum_posts", "Forum posts" ],
    torrent_comments: [ "torrent_comments", "Torrent comments" ]
  }.freeze

  # The latest stats of each tracker in the Prometheus text format, for the user's own Prometheus.
  # A stat the tracker doesn't report is left out, never sent as 0.
  def metrics
    latest = connections.includes(:site).sort_by { _1.site.slug }.filter_map { [ _1, _1.latest_snapshot ] if _1.latest_snapshot }
    families = METRICS.map do |stat, (name, help)|
      [ name, help, latest.filter_map { |connection, snapshot| [ connection, snapshot.public_send(stat) ] unless snapshot.public_send(stat).nil? } ]
    end
    families << [ "updated_timestamp_seconds", "When Sherlock saved these stats",
      latest.map { |connection, snapshot| [ connection, snapshot.created_at.to_i ] } ]
    families << [ "tracker_ok", "1 while Sherlock can update the tracker, 0 when it's failing, paused or needs a new key",
      latest.map { |connection, _| [ connection, connection.ok? ? 1 : 0 ] } ]

    families.reject { |_, _, samples| samples.empty? }.map do |name, help, samples|
      [ "# HELP sherlock_#{name} #{help}", "# TYPE sherlock_#{name} gauge",
        *samples.map { |connection, value| %(sherlock_#{name}{site="#{connection.site.slug}"} #{value.is_a?(BigDecimal) ? value.to_f : value}) } ]
    end.flatten.join("\n") + "\n"
  end

  IMPORT_COLUMNS = Snapshot.column_names - %w[id connection_id updated_at created_by_user_id import_batch_id]
  CROSS_SEED_IMPORT_COLUMNS = CrossSeedSnapshot.column_names - %w[id connection_id updated_at]

  # Adds the history from an #export file, from this Sherlock or a self-hosted one, to the trackers
  # this user has already added here. Exports never hold keys, so a tracker has to be added first.
  # Updates already here at the same second are skipped, so importing a file twice changes nothing.
  # Cross-seeds from qui come along; files from before they existed have none.
  # Returns the number of updates added and the names of trackers that aren't added yet.
  def import!(json)
    by_site = connections.includes(:site).index_by { _1.site.name }
    added = 0
    missing = []

    import_batch_id = SecureRandom.uuid
    transaction do
      JSON.parse(json).fetch("trackers").each do |tracker|
        connection = by_site[tracker.fetch("site")]
        next missing << tracker.fetch("site") unless connection

        added += import_rows(connection.snapshots, tracker.fetch("snapshots"), IMPORT_COLUMNS, provenance: true, import_batch_id:)
        import_rows(connection.cross_seed_snapshots, tracker.fetch("cross_seeds", []), CROSS_SEED_IMPORT_COLUMNS)
      end
    end
    [ added, missing ]
  rescue JSON::ParserError, KeyError, TypeError, ArgumentError, NoMethodError, ActiveRecord::StatementInvalid
    raise ArgumentError, "This file isn't a Sherlock export, or part of it can't be read. Nothing was imported."
  end

  private
    def import_rows(relation, snapshots, columns, provenance: false, import_batch_id: nil)
      known = relation.pluck(:created_at).to_set(&:to_i)
      rows = snapshots.filter_map do |snapshot|
        row = snapshot.slice(*columns)
        row["created_at"] = Time.iso8601(row.fetch("created_at")).change(usec: 0)
        raise ArgumentError if row["created_at"].future?
        # Numbers only. A plain cast would turn junk into 0, and 0 isn't the same as not reported.
        if provenance
          row["source"] = "json_import"
          row["created_by_user_id"] = id
          row["import_batch_id"] = import_batch_id
        end
        row.except("created_at", "user_class", "source", "note", "import_batch_id").each_value { Float(_1) unless _1.nil? }
        row.merge("updated_at" => row["created_at"]) if known.add?(row["created_at"].to_i)
      end
      relation.insert_all!(rows) if rows.any?
      rows.size
    end
end
