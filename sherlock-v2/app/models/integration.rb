# A service besides trackers that Sherlock reads for a user. qui is the only one so far. Who may use
# it works like a site's availability: everyone, admins and the people granted it, or nobody.
class Integration < ApplicationRecord
  enum :availability, { everyone: "everyone", granted: "granted", off: "off" }

  def self.qui
    find_by!(slug: "qui")
  end

  def available_to?(user)
    everyone? || (granted? && (user.is_admin? || user.integration_grants.exists?(integration: self)))
  end
end
