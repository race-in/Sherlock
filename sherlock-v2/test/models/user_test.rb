require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "native application defaults to invite-based multi-user mode" do
    assert_not Rails.application.config.x.single_user_mode
  end

  test "an invited account starts with isolated tracker data and remains in its inviter branch" do
    alice, bob = users(:alice), users(:bob)
    invite = alice.created_invites.create!
    carol = invite.accept!(username: "carol", password: "long-enough-pw", time_zone: "UTC")

    assert_equal alice, carol.invited_by_user
    assert_includes alice.branch, carol
    assert_includes alice.branch, bob
    assert_empty carol.connections
    assert_equal [ "Redacted" ], alice.connections.includes(:site).map { _1.site.name }.uniq
    assert_equal [ "Redacted" ], bob.connections.includes(:site).map { _1.site.name }.uniq
    assert_not_equal alice.connections.sole.id, bob.connections.sole.id
    assert_empty carol.metrics.strip
  end

  test "branch is everyone below a user in the invite tree" do
    assert_equal [ users(:alice), users(:bob) ].map(&:id).sort, User.branch_ids(users(:alice).id).sort
    assert_equal %w[bob], users(:alice).branch.map(&:username)
  end

  test "disabling a branch disables the user and everyone they invited and signs them out" do
    users(:bob).sessions.create!
    assert_equal 2, users(:alice).disable_branch!
    assert users(:alice).reload.is_disabled?
    assert users(:bob).reload.is_disabled?
    assert_not users(:admin).reload.is_disabled?
    assert_equal 0, users(:bob).sessions.count
  end

  test "reset password gives a working temporary password and forces a change" do
    password = users(:bob).reset_password!
    assert users(:bob).reload.authenticate(password)
    assert users(:bob).is_password_change_required?
  end

  test "export never includes keys or password" do
    json = users(:alice).export.to_json
    assert_includes json, "alice_red"
    assert_not_includes json, "alice-secret-key"
    assert_not_includes json, users(:alice).password_digest
    assert_not_includes json, "created_by_user_id"
    assert_not_includes json, "import_batch_id"
  end

  test "import adds history from an export to trackers already added, once" do
    alice, bob = users(:alice), users(:bob)
    connections(:alice_redacted).cross_seed_snapshots.create!(torrents: 9, size: 900, uploaded: 90, cross_seeded: 4,
      cross_seeded_size: 400, cross_seeded_uploaded: 40, cross_seeded_paused: 2, created_at: 2.hours.ago)
    export = alice.export.to_json
    bob_before = bob.connections.sole.snapshots.count

    assert_equal [ 2, [] ], bob.import!(export)
    assert_equal [ 0, [] ], bob.import!(export), "a second import adds nothing"

    imported = bob.connections.sole.snapshots.chronological.last(2)
    assert_equal [ 10737418240, 16106127360 ], imported.map(&:uploaded)
    assert_equal %w[json_import json_import], imported.map(&:source)
    assert_equal 1, imported.map(&:import_batch_id).uniq.size
    assert_match(/\A[0-9a-f-]{36}\z/, imported.first.import_batch_id)
    assert_equal [ nil, 12 ], imported.map(&:seeding), "not reported stays nil"
    assert_equal bob_before + 2, bob.connections.sole.snapshots.count
    cross_seed = bob.connections.sole.cross_seed_snapshots.sole
    assert_equal [ 9, 4, 400, 2 ], [ cross_seed.torrents, cross_seed.cross_seeded, cross_seed.cross_seeded_size, cross_seed.cross_seeded_paused ]

    # Exports from before cross-seeds existed still import.
    old = JSON.parse(export).tap { |file| file["trackers"].each { _1.delete("cross_seeds") } }.to_json
    assert_equal [ 0, [] ], bob.import!(old)
  end

  test "import names trackers that aren't added yet and rejects junk without saving anything" do
    bob = users(:bob)
    file = { trackers: [ { site: "Orpheus", snapshots: [ { created_at: 1.day.ago.iso8601, uploaded: 1, downloaded: 1 } ] } ] }.to_json
    assert_equal [ 0, [ "Orpheus" ] ], bob.import!(file)

    junk = { trackers: [ { site: "Redacted", snapshots: [
      { created_at: 2.days.ago.iso8601, uploaded: 5, downloaded: 1 },
      { created_at: 1.day.ago.iso8601, uploaded: "lots", downloaded: 1 }
    ] } ] }.to_json
    assert_no_difference -> { Snapshot.count } do
      assert_raises(ArgumentError) { bob.import!(junk) }
      assert_raises(ArgumentError) { bob.import!("not json") }
    end
  end

  test "usernames are encrypted at rest and still work for sign in" do
    raw = User.connection.select_value("SELECT username FROM users WHERE id = #{users(:alice).id}")
    assert_not_includes raw, "alice"
    raw = Connection.connection.select_rows("SELECT external_username, external_user_id FROM connections WHERE id = #{connections(:alice_redacted).id}").sole
    assert_not_includes raw.join, "alice_red"
    assert_equal users(:alice), User.find_by(username: " Alice ")
  end
end
