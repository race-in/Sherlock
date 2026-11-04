# Once a day, while the admin has update checks on, asks Codeberg for Sherlock's version tags and keeps
# the newest one. Admins see a notice when it's newer than what runs (InstanceSetting#available_update).
# Codeberg gets a plain GET with Sherlock's version in the User-Agent, and nothing about the instance.
class CheckForUpdateJob < ApplicationJob
  TAGS_URL = "https://codeberg.org/api/v1/repos/whatstatus/sherlock-v2/tags?limit=50"

  def perform
    setting = InstanceSetting.current
    return unless setting.is_update_check_enabled?

    response = Current.set(tracker_purpose: "update_check") { Engines::Http.get(TAGS_URL, site: nil, service: "codeberg") }
    return unless response.code == "200"

    newest = JSON.parse(response.body).filter_map { InstanceSetting.version_number(_1["name"]) }.reject(&:prerelease?).max
    setting.update!(latest_version: "v#{newest}", update_checked_at: Time.current) if newest
  end
end
