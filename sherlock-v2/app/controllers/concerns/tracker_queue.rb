# The trackers picked in "Add tracker", connected one per screen. Lives in the session so the pick
# survives a failed key without putting anything in the URL.
module TrackerQueue
  extend ActiveSupport::Concern

  included do
    helper_method :tracker_queue
  end

  private
    def tracker_queue
      Array(session[:tracker_queue])
    end

    def queue_trackers(slugs)
      session[:tracker_queue] = slugs
    end

    def dequeue_tracker(slug)
      session[:tracker_queue] = tracker_queue - [ slug ]
    end

    def next_tracker_path
      if (slug = tracker_queue.first)
        new_site_connection_path(site_slug: slug)
      elsif Current.user.onboarded?
        settings_connections_path
      else
        onboarding_completion_path
      end
    end
end
