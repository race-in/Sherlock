# The admin's first steps, shown on their dashboard until each is done or skipped. Each step reads its
# state from the data, so it's done the moment the admin does it, wherever they do it. Only the invite
# and update steps can be skipped: a Sherlock only its admin uses needs no invites, and update checks
# are off unless the admin turns them on. The first tracker waits for the contact, so the first request
# to a tracker already carries it.
class AdminSetup
  Step = Data.define(:key, :title, :hint, :done, :optional, :skipped) do
    alias_method :optional?, :optional
    alias_method :skipped?, :skipped

    def done?
      done || skipped
    end
  end

  def initialize(admin)
    @admin = admin
  end

  def steps
    @steps ||= begin
      setting = InstanceSetting.current
      skipped = setting.skipped_setup_steps
      [
        Step.new(:contact, "Add a contact for tracker staff",
          "An email address, your tracker username or an IRC channel. Every request to a tracker carries it, so staff can reach you before they block anything.",
          InstanceSetting.tracker_contact.present?, false, false),
        Step.new(:first_tracker, "Set up your first tracker",
          "Choose a tracker you're a member of and add your API key. Sherlock checks it right away. Then decide whether people you invite can track their stats there too.",
          @admin.connections.exists? || Site.where.not(availability: :off).exists?, false, false),
        Step.new(:invites, "Invite people", "One invite per person, or one for many that you post in a tracker's forum.",
          @admin.created_invites.exists?, true, skipped.include?("invites")),
        Step.new(:updates, "Check for updates", "Once a day, Sherlock asks Codeberg for the latest version.",
          setting.is_update_check_enabled?, true, skipped.include?("updates"))
      ]
    end
  end

  def complete?
    steps.all?(&:done?)
  end

  def next_step
    open = steps.reject { _1.done? || locked?(_1) }
    open.find { !_1.optional? } || open.first
  end

  def locked?(step)
    step.key == :first_tracker && !steps.first.done?
  end

  # Marks an optional step done without doing it. Raises KeyError for anything else.
  def skip!(key)
    step = steps.find { _1.key.to_s == key.to_s && _1.optional? } or raise KeyError, key
    setting = InstanceSetting.current
    setting.update!(skipped_setup_steps: (setting.skipped_setup_steps | [ step.key.to_s ]))
  end
end
