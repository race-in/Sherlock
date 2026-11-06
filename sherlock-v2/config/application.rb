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
  # Feral's front proxy strips the public subdirectory before forwarding to Puma.
  # Restore SCRIPT_NAME so Rails helpers, redirects, forms and Turbo requests keep
  # the public prefix while PATH_INFO remains relative to the Rails application.
  class FeralRelativeUrlRoot
    def initialize(app)
      @app = app
      @prefix = ENV.fetch("RAILS_RELATIVE_URL_ROOT", "").to_s.sub(/\/$/, "")
    end

    def call(env)
      env["SCRIPT_NAME"] = @prefix unless @prefix.empty?
      @app.call(env)
    end
  end

  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Optional reverse-proxy subdirectory deployment (for example "/sherlock").
    config.relative_url_root = ENV["RAILS_RELATIVE_URL_ROOT"].presence
    config.middleware.insert_before 0, Sherlock::FeralRelativeUrlRoot

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

    # Native deployment keeps the upstream invite-based multi-user model enabled by default.
    # Set SINGLE_USER_MODE=true only for an explicitly requested private single-account instance.
    config.x.single_user_mode = ENV["SINGLE_USER_MODE"] == "true"

    # The latest release tag, for the footer. Docker images and native installs set APP_VERSION.
    config.x.version = ENV.fetch("APP_VERSION") { `git describe --tags --abbrev=0 2>/dev/null`.strip.presence || "unknown" }

    # The public source repository, linked from the UI and the tracker User-Agent.
    config.x.source_url = "https://codeberg.org/whatstatus/sherlock-v2"

    # This instance's own host. Members' opt-in links point at it.
    config.x.app_host = ENV["APP_HOST"].presence || "localhost"

    # Generators write tests with fixtures and nothing we don't use.
    config.generators do |g|
      g.helper false
      g.jbuilder false
    end
  end
end
