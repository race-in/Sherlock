require "test_helper"

class PollConnectionJobTest < ActiveJob::TestCase
  test "poll all enqueues one job per pollable connection" do
    connections(:bob_redacted).pause!
    assert_enqueued_jobs 1, only: PollConnectionJob do
      PollAllConnectionsJob.perform_now
    end
  end

  test "poll all spreads users over the hour, each at their own slot" do
    travel_to Time.utc(2026, 10, 24, 18, 0, 3) do
      PollAllConnectionsJob.perform_now
    end
    scheduled = enqueued_jobs.select { _1["job_class"] == "PollConnectionJob" }.to_h do |job|
      [ GlobalID::Locator.locate(job["arguments"].first["_aj_globalid"]).user, Time.iso8601(job["scheduled_at"]) ]
    end

    assert_operator scheduled.size, :>=, 2
    assert_equal scheduled.size, scheduled.values.uniq.size
    scheduled.each do |user, at|
      assert_equal Time.utc(2026, 10, 24, 18) + user.poll_offset, at
      assert_operator at, :<, Time.utc(2026, 10, 24, 19)
    end
  end

  test "a rate limited poll waits for the next hourly poll, and doesn't count as a failure" do
    connection = connections(:alice_redacted)
    stub_tracker({ "index" => [ 429, "", { "Retry-After" => "9" } ] }) do
      assert_no_enqueued_jobs only: PollConnectionJob do
        PollConnectionJob.perform_now(connection)
      end
    end
    assert_equal 0, connection.reload.failure_count
    assert connection.ok?
  end
end
