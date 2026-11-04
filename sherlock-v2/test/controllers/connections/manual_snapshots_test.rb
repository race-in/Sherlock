require "test_helper"

class Connections::ManualSnapshotsControllerTest < ActionDispatch::IntegrationTest
  test "a member can append a manual snapshot to their own tracker history" do
    sign_in_as users(:alice)
    connection = connections(:alice_redacted)

    assert_difference -> { connection.snapshots.count }, 1 do
      post connection_manual_snapshot_path(connection), params: {
        snapshot: {
          uploaded: "1234567890123", downloaded: "456789012",
          ratio: "2.7000", required_ratio: "1.0000", bonus_points: "123.50",
          seeding: "12", leeching: "3", snatched: "99", hit_and_runs: "0",
          uploads: "7", forum_posts: "8", torrent_comments: "9",
          created_at: 2.hours.ago.strftime("%Y-%m-%dT%H:%M"), note: "Checked manually"
        }
      }
    end

    snapshot = connection.snapshots.order(created_at: :desc).first
    assert_redirected_to connection_path(connection)
    assert_equal "manual", snapshot.source
    assert_equal users(:alice), snapshot.created_by_user
    assert_equal 1_234_567_890_123, snapshot.uploaded
    assert_equal BigDecimal("2.7"), snapshot.ratio
    assert_equal "Checked manually", snapshot.note
    assert_predicate snapshot, :readonly?
  end

  test "a member cannot append history to another member's tracker" do
    sign_in_as users(:bob)
    connection = connections(:alice_redacted)

    assert_no_difference -> { connection.snapshots.count } do
      assert_raises(ActiveRecord::RecordNotFound) do
        post connection_manual_snapshot_path(connection), params: {
          snapshot: { uploaded: "1", downloaded: "1" }
        }
      end
    end
  end

  test "invalid negative, fractional count and future values do not create history" do
    sign_in_as users(:alice)
    connection = connections(:alice_redacted)

    [
      { uploaded: "-1", downloaded: "1" },
      { uploaded: "1", downloaded: "1", seeding: "1.5" },
      { uploaded: "1", downloaded: "1", created_at: 1.hour.from_now.strftime("%Y-%m-%dT%H:%M") },
      { uploaded: "1", downloaded: "1", note: "x" * 501 },
      { uploaded: "1", downloaded: "1", ratio: "1.12345" },
      { uploaded: "1", downloaded: "1", bonus_points: "123456789012345" }
    ].each do |attributes|
      assert_no_difference -> { connection.snapshots.count } do
        post connection_manual_snapshot_path(connection), params: { snapshot: attributes }
      end
    end
  end

  test "zero values remain zero and unreported optional metrics remain nil" do
    sign_in_as users(:alice)
    connection = connections(:alice_redacted)

    assert_difference -> { connection.snapshots.count }, 1 do
      post connection_manual_snapshot_path(connection), params: {
        snapshot: { uploaded: "0", downloaded: "0", seeding: "", ratio: "" }
      }
    end

    snapshot = connection.snapshots.order(created_at: :desc).first
    assert_equal 0, snapshot.uploaded
    assert_equal 0, snapshot.downloaded
    assert_nil snapshot.seeding
    assert_nil snapshot.ratio
  end

  test "uploaded and downloaded are required and large byte values stay exact" do
    sign_in_as users(:alice)
    connection = connections(:alice_redacted)

    assert_no_difference -> { connection.snapshots.count } do
      post connection_manual_snapshot_path(connection), params: { snapshot: { uploaded: "1" } }
    end

    assert_difference -> { connection.snapshots.count }, 1 do
      post connection_manual_snapshot_path(connection), params: {
        snapshot: { uploaded: "9223372036854775807", downloaded: "0" }
      }
    end
    assert_equal 9_223_372_036_854_775_807, connection.snapshots.order(created_at: :desc).first.uploaded
  end
end
