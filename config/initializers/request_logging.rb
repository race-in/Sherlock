# Rails starts every request log line with 'Started GET "/" for <IP address>'. Sherlock doesn't keep
# IP addresses, so the line leaves it out.
Rails::Rack::Logger.prepend(Module.new do
  private
    def started_request_message(request)
      format('Started %s "%s" at %s', request.raw_request_method, request.filtered_path, Time.now)
    end
end)
