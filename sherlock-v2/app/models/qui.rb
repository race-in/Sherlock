# Reads the torrents of every qBittorrent instance in a user's qui (https://getqui.com). Sends only GET
# requests: a qui API key can do anything the qui user can, deleting torrents included, so Sherlock
# never sends anything else. Error messages are shown to users and saved, so they never contain the key.
class Qui
  PAGE_SIZE = 2000 # The most qui returns in one page.
  MAX_PAGES = 100
  # A qui is the user's own server, so a broken or hostile one mustn't hold a job worker for long.
  MAX_INSTANCES = 20
  DEADLINE = 3.minutes
  SEEDING_STATES = %w[uploading stalledUP queuedUP forcedUP].freeze
  PAUSED_STATES = %w[pausedUP stoppedUP].freeze

  # is_seeding: complete, in a seeding state, and the tracker answers without an error.
  # is_paused: the same, but paused in the torrent client.
  Torrent = Data.define(:instance_id, :content_path, :tracker_host, :size, :uploaded, :is_seeding, :is_paused)

  # local: allows private addresses and plain http, see QuiConnection.
  def initialize(url, api_key, local: false)
    @base = "#{url.chomp("/")}/api/"
    @api_key = api_key
    @local = local
  end

  def torrents
    @deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DEADLINE
    instances = get("instances")
    raise Engines::Error, "qui didn't list its instances. Check the address." unless instances.is_a?(Array) && instances.all?(Hash)

    # A switched-off instance, or one qui can't reach, answers with an error instead of torrents.
    ids = instances.select { _1["isActive"] != false && _1["connected"] != false }.filter_map { Integer(_1["id"], exception: false) }
    raise Engines::Error, "qui lists more than #{MAX_INSTANCES} instances. Sherlock reads at most #{MAX_INSTANCES}." if ids.size > MAX_INSTANCES

    ids.flat_map { instance_torrents(_1) }
  end

  private
    def instance_torrents(instance_id)
      (0...MAX_PAGES).each_with_object([]) do |page, torrents|
        body = get("instances/#{instance_id}/torrents", page:, limit: PAGE_SIZE)
        rows = body["torrents"] || []
        torrents.concat(rows.map { torrent(instance_id, _1) })
        break torrents if rows.size < PAGE_SIZE || body["hasMore"] == false
      end
    end

    def torrent(instance_id, row)
      # qBittorrent's "tracker" is the announce URL that last worked, and empty when none did.
      host = row["tracker"].to_s[%r{\A[a-z]+://([^/:?]+)}i, 1].to_s.downcase
      healthy = row["progress"].to_f >= 1 && host.present? && row["tracker_health"].blank?
      Torrent.new(
        instance_id:, content_path: row["content_path"].to_s, tracker_host: host,
        size: row["size"].to_i, uploaded: row["uploaded"].to_i,
        is_seeding: healthy && SEEDING_STATES.include?(row["state"]), is_paused: healthy && PAUSED_STATES.include?(row["state"])
      )
    end

    def get(path, params = {})
      raise Engines::Error, "qui took longer than #{DEADLINE.inspect} to list its torrents." if Process.clock_gettime(Process::CLOCK_MONOTONIC) > @deadline

      url = "#{@base}#{path}#{"?#{params.to_query}" if params.any?}"
      response = Engines::Http.get(url, { "X-API-Key" => @api_key }, site: nil, local: @local)
      case response.code.to_i
      when 200 then JSON.parse(response.body)
      when 401, 403 then raise Engines::AccessDenied, "qui refused the API key."
      else raise Engines::Error, "qui answered with HTTP #{response.code}. Check the address."
      end
    rescue JSON::ParserError
      raise Engines::Error, "qui didn't answer with JSON. Check the address."
    end
end
