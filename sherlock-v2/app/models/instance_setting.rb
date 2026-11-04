# Settings for the whole instance, in one row that's made on first use.
class InstanceSetting < ApplicationRecord
  normalizes :tracker_contact, with: ->(contact) { contact.strip.presence }
  validates :tracker_contact, length: { maximum: 200 }
  validates :tracker_contact, presence: { message: "is needed while a tracker reads profiles with your key" }, if: -> { Site.instance_key.exists? }

  # Turning update checks off anywhere answers the setup's question too (AdminSetup).
  before_save -> { self.skipped_setup_steps |= [ "updates" ] }, if: -> { is_update_check_enabled_changed?(from: true, to: false) }

  def self.current
    first || create!
  rescue ActiveRecord::RecordNotUnique
    first
  end

  # Where tracker staff reach the person running this Sherlock: an email address, their
  # username on the trackers, or an IRC channel.
  def self.tracker_contact
    current.tracker_contact
  end

  # The newest version from the last update check (CheckForUpdateJob), if it's newer than the one
  # running. nil while checks are off, and for builds that don't know their version.
  def available_update
    return unless is_update_check_enabled? && latest_version

    running = self.class.version_number(Rails.configuration.x.version)
    latest = self.class.version_number(latest_version)
    latest_version if running && latest && latest > running
  end

  # "v1.0.10" as a Gem::Version, so it sorts after "v1.0.9". nil for anything else, like "unknown".
  def self.version_number(tag)
    number = tag.to_s.delete_prefix("v")
    Gem::Version.new(number) if Gem::Version.correct?(number) && number.present?
  end
end
