require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
# require "active_storage/engine"
require "action_controller/railtie"
# require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Sherlock
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # schema.rb can't hold the set_updated_at() function, its triggers, or CHECK-heavy enums.
    config.active_record.schema_format = :sql

    # /jobs uses Sherlock's own sign in and admin check instead of HTTP basic auth.
    config.mission_control.jobs.base_controller_class = "Admin::BaseController"
    config.mission_control.jobs.http_basic_auth_enabled = false

    # The latest release tag, for the footer. Images get APP_VERSION at build time.
    config.x.version = ENV.fetch("APP_VERSION") { `git describe --tags --abbrev=0 2>/dev/null`.strip.presence || "unknown" }

    # The public source repository, linked from the UI and the tracker User-Agent.
    config.x.source_url = "https://github.com/race-in/Sherlock"

    # This instance's own host. Members' opt-in links point at it.
    config.x.app_host = ENV["APP_HOST"].presence || "localhost"

    # Generators write tests with fixtures and nothing we don't use.
    config.generators do |g|
      g.helper false
      g.jbuilder false
    end
  end
end
