# Replaces Engines::Http.get for one block. Tests never call real trackers.
# responses: { "index" => [status, body], ... } keyed by ajax action, by api.php request for GazelleGames,
# or by path for APIs without either, like "/api/user" on UNIT3D.
module TrackerStub
  Response = Struct.new(:code, :body, :headers) do
    def [](name) = headers[name]
  end

  def stub_tracker(responses)
    requests = []
    original = Engines::Http.method(:get)
    Engines::Http.define_singleton_method(:get) do |url, headers = {}, site:, **string_headers|
      uri = URI(url)
      requests << { uri:, headers: headers.merge(string_headers), site: }
      params = URI.decode_www_form(uri.query.to_s).to_h
      action = params["action"] || params["request"] || uri.path
      code, body, extra = responses.fetch(action)
      Response.new(code.to_s, body, extra || {})
    end
    yield requests
  ensure
    Engines::Http.define_singleton_method(:get, original)
  end

  # Replaces Engines::Http.post for one block, for trackers that take a JSON body (HDBits, BTN).
  # responses: [status, body] pairs, answered in order; the last one repeats.
  def stub_tracker_post(*responses)
    requests = []
    original = Engines::Http.method(:post)
    Engines::Http.define_singleton_method(:post) do |url, body, headers = {}, site:|
      requests << { uri: URI(url), body:, site: }
      code, text, extra = responses.size > 1 ? responses.shift : responses.first
      Response.new(code.to_s, text, extra || {})
    end
    yield requests
  ensure
    Engines::Http.define_singleton_method(:post, original)
  end

  def tracker_file(site, action)
    [ 200, file_fixture("#{site}/#{action}.json").read ]
  end

  def stub_redacted_success(&)
    stub_tracker({ "index" => tracker_file("redacted", "index"), "community_stats" => tracker_file("redacted", "community_stats"),
                   "user" => tracker_file("redacted", "user") }, &)
  end
end
