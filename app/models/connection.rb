class Connection < ApplicationRecord
  FAILURES_BEFORE_FAILING = 3
  # "Update now" and "Test now" leave a tracker alone for this long after it was last asked.
  RECENT = 15.minutes

  belongs_to :user
  belongs_to :site
  has_many :snapshots
  has_many :cross_seed_snapshots

  encrypts :credential, :external_username, :external_user_id

  # needs_check: on an instance-key site, Sherlock stopped reading the member's profile until they click
  # Check, because their opt-in link is gone, the account is disabled, or the profile hides too much.
  enum :status, { ok: "ok", failing: "failing", needs_key: "needs_key", paused: "paused", needs_check: "needs_check" }

  validates :site_id, uniqueness: { scope: :user_id, message: "is already added" }
  validates :color, format: { with: /\A#[0-9a-f]{6}\z/, message: "must be a hex color like #1f7fa6" }, allow_nil: true
  before_validation { self.color = color.presence&.downcase }

  # Only trackers the user may still use (Site.available_to): taking back a grant stops its polls, and
  # so does a paused site. A connection also needs what its site reads with: the member's key, or on an
  # instance-key site the code of their opt-in link, or for the key's own account, the key.
  scope :pollable, -> {
    where(status: %i[ok failing]).joins(:user, :site).merge(User.enabled).where(<<~SQL)
      (sites.availability = 'everyone' OR (sites.availability = 'granted' AND (users.is_admin OR EXISTS (
        SELECT 1 FROM site_grants WHERE site_grants.user_id = connections.user_id AND site_grants.site_id = connections.site_id))))
      AND (sites.pause_reason IS NULL OR sites.paused_until <= now())
      AND ((sites.key_owner = 'member' AND connections.credential IS NOT NULL)
        OR (sites.key_owner = 'instance' AND (connections.profile_code IS NOT NULL OR connections.is_key_owner)))
    SQL
  }

  # The user's own order from Settings → Trackers. A new tracker goes to the end.
  scope :ordered, -> { joins(:site).order(:position, "sites.name") }
  before_create { self.position = user.connections.maximum(:position)&.next || 0 }

  # An open page of this user's morphs in new numbers whenever a poll finishes.
  broadcasts_refreshes_to ->(connection) { connection.user }

  # Saved only after the tracker accepted the key, together with the first snapshot.
  # stats: what the tracker answered for this key already, so it isn't asked twice (Admin::Sites::SetupsController).
  def self.connect!(user:, site:, api_key:, stats: nil)
    raise Engines::Error, "#{site.name} can't be added." unless site.available_to?(user) && site.member_key?
    raise Engines::Error, "You already added #{site.name}." if user.connections.exists?(site:)
    raise Engines::Error, "Sherlock is full for #{site.name} right now." if site.full?

    stats ||= site.adapter.fetch(api_key)
    transaction do
      user.connections.create!(site:, credential: api_key, external_user_id: stats.external_user_id,
        external_username: stats.external_username, polled_at: Time.current).tap do |connection|
        connection.snapshots.create!(stats.snapshot_attributes)
      end
    end
  end

  # A member's profile on an instance-key site, once Check found their opt-in link on it (ProfileClaim),
  # with the stats that Check read as the first snapshot. The site's row lock keeps one tracker account
  # on one Sherlock account, and the site within its capacity.
  def self.connect_profile!(user:, claim:)
    site = claim.site
    raise Engines::Error, "#{site.name} can't be added." unless site.available_to?(user) && site.instance_key?

    transaction do
      site.lock!
      raise Engines::Error, "You already added #{site.name}." if user.connections.exists?(site:)
      raise Engines::Error, "This #{site.name} account is already on Sherlock." if site.account_taken?(claim.external_user_id)
      raise Engines::Error, "Sherlock is full for #{site.name} right now." if site.full?

      user.connections.create!(site:, profile_code: claim.profile_code, external_user_id: claim.external_user_id,
        external_username: claim.external_username, polled_at: claim.checked_at).tap do |connection|
        connection.snapshots.create!(claim.stats.snapshot_attributes)
      end
    end
  end

  # The admin's own account on a site read with their key. The key reads it like a member's own key
  # would, with every stat, so it needs no opt-in link.
  def self.connect_key_owner!(user:, site:)
    raise Engines::Error, "#{site.name} can't be added." unless user.is_admin? && site.available_to?(user) && site.instance_key?
    raise Engines::Error, "You already added #{site.name}." if user.connections.exists?(site:)

    stats = site.adapter.fetch(site.instance_credential)
    transaction do
      site.lock!
      raise Engines::Error, "This #{site.name} account is already on Sherlock." if site.account_taken?(stats.external_user_id)

      user.connections.create!(site:, is_key_owner: true, external_user_id: stats.external_user_id,
        external_username: stats.external_username, polled_at: Time.current).tap do |connection|
        connection.snapshots.create!(stats.snapshot_attributes)
      end
    end
  end

  # When the instance key turns out to be this account's own (Site#use_instance_key!).
  def read_with_instance_key!
    update!(is_key_owner: true, credential: nil, profile_code: nil, error_message: nil, failure_count: 0,
      status: paused? ? :paused : :ok)
  end

  # Raises Engines::Withheld when Sherlock held back (the site is paused or busy, or the tracker asked it
  # to slow down). That isn't the connection's fault, so it changes nothing.
  def poll!
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    refuse_unless_available!
    record(fetch_stats)
    Rails.event.notify("poll.succeeded", site: site.slug, connection_id: id, duration: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
    true
  rescue Engines::Withheld
    raise
  rescue Engines::CheckNeeded => error
    failed(error, status: :needs_check, started:)
  rescue Engines::AccessDenied => error
    failed(error, status: :needs_key, started:)
  rescue Engines::Error => error
    failed(error, status: status_after_error, started:)
  end

  # Raises Engines::Error when the tracker refuses the new key, and leaves the old one in place. The key
  # must belong to the same tracker account, so the history stays one account's.
  def replace_key!(api_key)
    refuse_unless_available!
    raise Engines::Error, "#{site.name} reads your profile on this Sherlock, not a key." if site.instance_key?

    stats = site.adapter.fetch(api_key)
    if stats.external_user_id != external_user_id
      raise Engines::Error, "That key belongs to another #{site.name} account. Use a key from #{external_username}."
    end

    transaction do
      self.credential = api_key
      self.status = :ok
      record(stats)
    end
  end

  # ids in the order the user dragged them into. Ids that aren't the user's are ignored, and trackers
  # left out keep their place after the ones given.
  def self.reorder!(user, ids)
    connections = user.connections.ordered.to_a
    ordered = ids.filter_map { |id| connections.find { _1.id == id.to_i } }.uniq
    transaction do
      (ordered + (connections - ordered)).each_with_index { |connection, position| connection.update_column(:position, position) }
    end
  end

  def pause!
    update!(status: :paused)
  end

  def resume!
    update!(status: :ok, failure_count: 0, error_message: nil) if paused?
  end

  def latest_snapshot
    @latest_snapshot ||= snapshots.order(created_at: :desc).first
  end

  def history(range)
    History.new(self, range:)
  end

  def change(since:)
    History.change(self, since:)
  end

  def next_poll_at
    user.next_poll_at if ok? || failing?
  end

  # "Update now" and "Test now" skip a tracker asked this recently.
  def recently_polled?
    polled_at.present? && polled_at > RECENT.ago
  end

  def profile?
    profile_code.present?
  end

  # The color the charts draw this tracker with: the user's pick, or the site default until they do.
  def display_color
    color || site.default_color
  end

  private
    def refuse_unless_available!
      raise Engines::Error, "#{site.display_name} isn't available to you on this Sherlock." unless site.available_to?(user)
    end

    def fetch_stats
      if site.instance_key? && is_key_owner?
        begin
          site.adapter.fetch(site.instance_credential)
        rescue Engines::AccessDenied
          site.pause!(:key_refused)
          raise Engines::Paused, "#{site.name} refused the admin's key. Sherlock reads nobody there until the admin saves one that works."
        end
      elsif site.instance_key?
        site.adapter.fetch_profile(external_user_id, profile_code).tap do |stats|
          raise Engines::CheckNeeded, "Your #{site.name} profile hides your uploaded or downloaded amount, so Sherlock has nothing to chart." unless stats.trackable?
        end
      else
        raise Engines::AccessDenied, "Sherlock has no key for #{site.name}. Add one to keep tracking." if credential.nil?

        site.adapter.fetch(credential)
      end
    end

    def record(stats)
      transaction do
        snapshots.create!(stats.snapshot_attributes)
        update!(status: status_after_success, polled_at: Time.current, error_message: nil, failure_count: 0,
          external_username: stats.external_username)
      end
      @latest_snapshot = nil
    end

    def failed(error, status:, started:)
      update!(status:, polled_at: Time.current, error_message: error.message.truncate(500), failure_count: failure_count + 1)
      Rails.event.notify("poll.failed", site: site.slug, connection_id: id, error: error.class.name, status:,
        duration: Process.clock_gettime(Process::CLOCK_MONOTONIC) - started)
      false
    end

    def status_after_success
      paused? ? :paused : :ok
    end

    # A passing error doesn't undo a status that waits for the member, like needs_key or needs_check.
    def status_after_error
      return status unless ok? || failing?

      failure_count + 1 >= FAILURES_BEFORE_FAILING ? :failing : :ok
    end
end
