class PollAllConnectionsJob < ApplicationJob
  # Runs on the hour (config/recurring.yml) and schedules each poll for its user's slot in that hour.
  def perform
    hour = Time.current.beginning_of_hour
    Connection.pollable.includes(:user).find_each do |connection|
      PollConnectionJob.set(wait_until: hour + connection.user.poll_offset).perform_later(connection)
    end

    qui = Integration.qui
    User.enabled.where(id: QuiConnection.select(:user_id)).where.not(id: QuiConnection.where(is_key_refused: true).select(:user_id)).find_each do |user|
      next unless qui.available_to?(user)

      PollQuiJob.set(wait_until: hour + user.poll_offset).perform_later(user)
    end
  end
end
