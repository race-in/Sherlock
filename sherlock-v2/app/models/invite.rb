class Invite < ApplicationRecord
  TTL = 14.days

  class Unusable < StandardError; end

  belongs_to :created_by_user, class_name: "User", inverse_of: :created_invites
  # Only for open invites: they then let in only this tracker's members.
  belongs_to :site, optional: true
  has_many :users, inverse_of: :invite

  has_secure_token :code, length: 24

  attribute :expires_at, default: -> { TTL.from_now }

  validates :max_uses, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :open_only_for_admins, on: :create

  scope :usable, -> {
    where(revoked_at: nil).where("invites.expires_at IS NULL OR invites.expires_at > ?", Time.current)
      .where("invites.max_uses IS NULL OR invites.uses < invites.max_uses")
  }
  # Invites that use up one of the creator's slots: used ones, and unused ones still waiting.
  scope :counted, -> { where("invites.uses > 0").or(usable) }
  scope :newest_first, -> { order(created_at: :desc) }

  def to_param
    code
  end

  # An admin's invite for more than one person. Whoever uses it proves a tracker profile first, with the
  # instance key, so a code posted in a forum only lets that tracker's members in.
  def open?
    max_uses != 1
  end

  # The trackers whose members can join with this open invite.
  def joinable_sites
    site_id ? Site.joinable.where(id: site_id) : Site.joinable
  end

  def status
    if revoked_at then :revoked
    elsif max_uses && uses >= max_uses then :full
    elsif expires_at&.past? then :expired
    elsif uses.positive? then :in_use
    else :unused
    end
  end

  def usable?
    status.in?(%i[unused in_use])
  end

  # Signs a new user up with this invite. The row lock stops two people taking its last use at once. An
  # open invite also saves the profile the new user checked (ProfileClaim), or nobody joins.
  def accept!(username:, password:, time_zone:, claim: nil)
    transaction do
      lock!
      raise Unusable unless usable?
      raise Engines::Error, "Check your profile again, then create your account." if open? && !(claim&.ready? && joinable_sites.include?(claim.site))

      increment!(:uses)
      User.create!(username:, password:, time_zone:, invited_by_user: created_by_user, invite: self).tap do |user|
        Connection.connect_profile!(user:, claim:) if open?
      end
    end
  end

  def revoke!
    update!(revoked_at: Time.current) if usable?
  end

  private
    def open_only_for_admins
      return unless open? || expires_at.nil?

      if !created_by_user&.is_admin?
        errors.add(:base, "Only admins can make invites for more than one person or without an end.")
      elsif open? && !joinable_sites.exists?
        errors.add(:base, "Invites for more than one person need a tracker that uses your key for everyone.")
      end
      errors.add(:base, "Only invites for more than one person can be for one tracker.") if site_id && !open?
    end
end
