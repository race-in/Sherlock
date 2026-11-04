# Replaces Engines::Http.get for one block with a fake qui. Tests never call a real qui.
module QuiStub
  # servers: { host => { instance_id => rows } }, served in pages like qui does, or { host => status }
  # for a qui that only answers with that HTTP status.
  def stub_qui(servers, &)
    stub_qui_http(->(uri) {
      torrents = servers.fetch(uri.host)
      next [ torrents, "<html>nope</html>" ] if torrents.is_a?(Integer)
      # An instance whose rows are :disconnected is one qui can't reach: listed, but its torrents fail.
      next [ 200, torrents.map { |id, rows| { "id" => id, "isActive" => true, "connected" => rows != :disconnected } }.to_json ] if uri.path.end_with?("/api/instances")
      next [ 500, { error: "Failed to get torrents" }.to_json ] if torrents[uri.path[%r{/instances/(\d+)/torrents}, 1].to_i] == :disconnected

      rows = torrents.fetch(uri.path[%r{/instances/(\d+)/torrents}, 1].to_i)
      params = URI.decode_www_form(uri.query).to_h
      limit, page = params["limit"].to_i, params["page"].to_i
      [ 200, { torrents: rows.slice(page * limit, limit) || [], total: rows.size, hasMore: (page + 1) * limit < rows.size }.to_json ]
    }, &)
  end

  def stub_qui_status(code, &)
    stub_qui_http(->(_uri) { [ code, "<html>nope</html>" ] }, &)
  end

  def stub_qui_http(responder)
    requests = []
    original = Engines::Http.method(:get)
    Engines::Http.define_singleton_method(:get) do |url, headers = {}, site:, local: false|
      uri = URI(url)
      requests << { uri:, headers:, local: }
      code, body = responder.call(uri)
      TrackerStub::Response.new(code.to_s, body, {})
    end
    yield requests
  ensure
    Engines::Http.define_singleton_method(:get, original)
  end
end
