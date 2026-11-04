# One adapter per tracker engine. Each takes a Site and answers #fetch(api_key) with Stats, or
# raises one of the errors below. Error messages are shown to users and saved, so they must never
# contain the key.
module Engines
  class Error < StandardError; end

  # The tracker refused the key: wrong, revoked or missing permission. Polling stops until the user
  # replaces it.
  class AccessDenied < Error; end

  # Sherlock read a member's profile with the instance key, but has to stop until the member clicks
  # Check: the opt-in link is gone, the account is disabled, or the profile hides what Sherlock needs.
  class CheckNeeded < Error; end

  # Sherlock held back instead of asking the tracker, or the tracker told it to. Nothing is wrong with
  # the member's connection, so its status and failure count stay as they are.
  class Withheld < Error; end

  # The site is paused (see Site#pause!), so nothing is sent to it.
  class Paused < Withheld; end

  # The site's next free request slot is further away than the caller may wait.
  class Busy < Withheld; end

  # The tracker answered 429 or its own rate limit error. The site is paused by then.
  class RateLimited < Withheld; end

  # Stats a profile must show for Sherlock to chart anything at all.
  PROFILE_NEEDED = %i[uploaded downloaded].freeze

  # nil in any field means the tracker doesn't report it, or the member's paranoia hides it, and the
  # UI hides it.
  Stats = Data.define(
    :external_user_id, :external_username,
    :uploaded, :downloaded, :ratio, :required_ratio, :bonus_points,
    :seeding, :leeching, :snatched, :hit_and_runs, :user_class,
    :uploads, :forum_posts, :torrent_comments
  ) do
    def snapshot_attributes
      to_h.except(:external_user_id, :external_username)
    end

    def trackable?
      PROFILE_NEEDED.none? { public_send(_1).nil? }
    end
  end

  # Whether a profile's text holds this instance's opt-in link with the member's code. Trackers may link
  # through a redirector or encode the URL, so it's matched decoded and anywhere in the text.
  def self.opt_in_link?(text, code)
    host = Regexp.escape(Rails.configuration.x.app_host)
    CGI.unescape(text.to_s).match?(%r{//(?:www\.)?#{host}(?::\d+)?/opt-in/#{Regexp.escape(code)}(?![a-z0-9])}i)
  end

  def self.for(site)
    const_get(site.engine.camelize).new(site)
  end
end
