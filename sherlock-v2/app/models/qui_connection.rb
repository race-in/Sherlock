# One of a user's qui instances, read once an hour for what seeds where. Only admins' quis may be on a
# private network or plain http: anyone else could otherwise make the server reach into its own network.
class QuiConnection < ApplicationRecord
  # Torrents this size or larger with exactly the same size count as the same files. qui's hardlink and
  # reflink modes give a cross-seed its own folder, so the content path alone misses those.
  SAME_SIZE_MINIMUM = 16.megabytes

  belongs_to :user

  encrypts :credential

  validates :url, format: { with: %r{\Ahttps?://[^\s/]+[^\s]*\z}, message: "must start with http:// or https://" }, length: { maximum: 300 }
  validates :label, length: { maximum: 60 }
  before_validation { self.url = url.to_s.strip.chomp("/") }
  before_validation { self.label = label.to_s.strip.presence }

  # Saved only after qui accepted the key, then the user's quis are all read again. Adding an address
  # the user already has replaces its key.
  def self.connect!(user:, url:, api_key:, label: nil)
    raise Engines::Error, "qui isn't available to you on this Sherlock." unless Integration.qui.available_to?(user)

    connection = user.qui_connections.find_or_initialize_by(url: url.to_s.strip.chomp("/"))
    connection.assign_attributes(credential: api_key.to_s.strip, polled_at: Time.current, error_message: nil, is_key_refused: false)
    connection.label = label if label.present?
    connection.validate!
    Qui.new(connection.url, connection.credential, local: user.is_admin?).torrents
    connection.save!
    poll!(user)
    connection
  end

  # Reads every qui of the user and saves one snapshot per tracker from all of them together. When one
  # qui fails, nothing is saved for that hour, since its torrents would be missing from the counts.
  # A qui that refused its key isn't contacted again until the user replaces the key, and none is once the
  # user may no longer use qui. Returns whether all of them answered.
  def self.poll!(user)
    return false unless Integration.qui.available_to?(user)

    quis = user.qui_connections.order(:id).to_a
    return false if quis.any?(&:is_key_refused)

    torrents = quis.map(&:fetch)
    return false if torrents.any?(&:nil?)

    record(user, quis, torrents.flatten)
    true
  end

  # This qui's torrents, or nil with the error saved. Instances are told apart by qui too, since two quis
  # may both number theirs from 1.
  def fetch
    torrents = Qui.new(url, credential, local: user.is_admin?).torrents.map { _1.with(instance_id: [ id, _1.instance_id ]) }
    update!(polled_at: Time.current, error_message: nil)
    torrents
  rescue Engines::Error => error
    update!(polled_at: Time.current, error_message: error.message.truncate(500), is_key_refused: error.is_a?(Engines::AccessDenied))
    nil
  end

  # One snapshot per tracker of the user's that has seeding or paused torrents, and each qui's own totals.
  def self.record(user, quis, torrents)
    seeding = torrents.select(&:is_seeding)
    complete = torrents.select { _1.is_seeding || _1.is_paused }
    sites = Site.where.not(tier: :unsupported).to_a
    tracker_of = complete.to_h { |torrent| [ torrent, sites.find { _1.tracker_host?(torrent.tracker_host) }&.slug || torrent.tracker_host ] }
    shared = cross_seeded(seeding, tracker_of)
    # Cross-seeds qui matched where this copy or the other one is paused.
    paused = cross_seeded(complete, tracker_of) - shared

    transaction do
      user.connections.includes(:site).each do |connection|
        on_tracker = complete.select { connection.site.tracker_host?(_1.tracker_host) }
        next if on_tracker.empty?

        own = on_tracker.select(&:is_seeding)
        crossed = own.select { shared.include?(_1) }
        connection.cross_seed_snapshots.create!(
          torrents: own.size, size: own.sum(&:size), uploaded: own.sum(&:uploaded),
          cross_seeded: crossed.size, cross_seeded_size: crossed.sum(&:size), cross_seeded_uploaded: crossed.sum(&:uploaded),
          cross_seeded_paused: on_tracker.count { paused.include?(_1) }
        )
      end

      quis.each do |qui|
        own = complete.select { _1.instance_id.first == qui.id }
        qui.update!(seeding: own.count(&:is_seeding), cross_seeded: own.count { shared.include?(_1) },
          cross_seeded_paused: own.count { paused.include?(_1) })
      end
    end
  end

  # Torrents whose files are also on another tracker in the same qBittorrent. Files are the same when
  # the content path is, or when the size is to the byte. Groups are joined through either.
  def self.cross_seeded(torrents, tracker_of)
    # Union-find over torrents and the keys they share.
    parent = Hash.new { |hash, key| hash[key] = key }
    root = ->(key) { key = parent[key] = parent[parent[key]] while parent[key] != key; key }

    torrents.each do |torrent|
      keys = []
      keys << [ :path, torrent.instance_id, torrent.content_path ] if torrent.content_path.present?
      keys << [ :size, torrent.instance_id, torrent.size ] if torrent.size >= SAME_SIZE_MINIMUM
      keys.each { parent[root.(_1)] = root.(torrent) }
    end

    torrents.group_by { root.(_1) }.values
      .select { |group| group.map { tracker_of[_1] }.uniq.many? }
      .flatten.to_set
  end
  private_class_method :record, :cross_seeded

  # What the settings page calls this qui: the user's name for it, or its address.
  def name
    label || address
  end

  # The address without the scheme, which is almost always http.
  def address
    URI(url).then { "#{_1.host}#{":#{_1.port}" unless _1.port == _1.default_port}#{_1.path}" }
  rescue URI::InvalidURIError
    url
  end
end
