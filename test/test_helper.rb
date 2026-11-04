ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/tracker_stub"
require_relative "test_helpers/qui_stub"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all
    include TrackerStub
    include QuiStub

    # The per-site gate (Site#reserve_request!) still spaces requests in tests; nothing actually waits.
    setup { Engines::Http.sleeper = ->(_) { } }
  end
end
