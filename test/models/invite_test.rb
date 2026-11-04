require "test_helper"

class InviteTest < ActiveSupport::TestCase
  test "accepting creates a user under the inviter and spends the invite once" do
    invite = invites(:alice_unused)
    user = invite.accept!(username: "Carol ", password: "long-enough-pw", time_zone: "UTC")

    assert_equal "carol", user.username
    assert_equal users(:alice), user.invited_by_user
    assert_equal :full, invite.reload.status
    assert_raises(Invite::Unusable) { invite.accept!(username: "dave", password: "long-enough-pw", time_zone: "UTC") }
  end

  test "expired and revoked invites can't be used" do
    assert_raises(Invite::Unusable) { invites(:alice_expired).accept!(username: "dave", password: "long-enough-pw", time_zone: "UTC") }
    invites(:alice_unused).revoke!
    assert_raises(Invite::Unusable) { invites(:alice_unused).accept!(username: "dave", password: "long-enough-pw", time_zone: "UTC") }
  end

  test "a bad username leaves the invite unused" do
    assert_raises(ActiveRecord::RecordInvalid) { invites(:alice_unused).accept!(username: "x", password: "long-enough-pw", time_zone: "UTC") }
    assert invites(:alice_unused).reload.usable?
  end

  test "unused and used invites count against the limit, expired and revoked don't" do
    alice = users(:alice)
    assert_equal 1, alice.invites_left
    alice.created_invites.create!
    assert_equal 0, alice.invites_left
    assert_not alice.can_invite?
    invites(:alice_unused).revoke!
    assert_equal 1, alice.invites_left
  end

  test "an open invite takes as many people as it allows, each with a checked profile" do
    site = make_joinable
    invite = users(:admin).created_invites.create!(max_uses: 2, expires_at: nil)

    error = assert_raises(Engines::Error) { invite.accept!(username: "carol", password: "[REDACTED:password]", time_zone: "UTC") }
    assert_match "Check your profile", error.message

    %w[carol dave].each.with_index(1) do |name, id|
      user = invite.accept!(username: name, password: "[REDACTED:password]", time_zone: "UTC", claim: ready_claim(site, "90#{id}"))
      assert_equal "90#{id}", user.connections.sole.external_user_id
      assert user.connections.sole.snapshots.exists?
    end

    assert_equal :full, invite.reload.status
    assert_raises(Invite::Unusable) { invite.accept!(username: "erin", password: "[REDACTED:password]", time_zone: "UTC", claim: ready_claim(site, "903")) }
  end

  test "a tracker account joins only once" do
    site = make_joinable
    invite = users(:admin).created_invites.create!(max_uses: nil)
    invite.accept!(username: "carol", password: "[REDACTED:password]", time_zone: "UTC", claim: ready_claim(site, "901"))

    assert_no_difference -> { User.count } do
      assert_raises(Engines::Error) { invite.accept!(username: "dave", password: "[REDACTED:password]", time_zone: "UTC", claim: ready_claim(site, "901")) }
    end
  end

  test "only admins make invites for more than one person or without an end" do
    make_joinable
    assert_not users(:alice).created_invites.create(max_uses: 5).persisted?
    assert_not users(:alice).created_invites.create(expires_at: nil).persisted?
    assert users(:admin).created_invites.create(max_uses: 5, expires_at: nil).persisted?
  end

  private
    def make_joinable
      sites(:redacted).tap do |site|
        Connection.where(site:).update_all(credential: nil, profile_code: nil)
        site.update!(key_owner: :instance, instance_credential: "admin-key")
      end
    end

    def ready_claim(site, user_id)
      stats = Engines::Stats.new(external_user_id: user_id, external_username: "member#{user_id}", uploaded: 10, downloaded: 5,
        ratio: 2, required_ratio: nil, bonus_points: nil, seeding: nil, leeching: nil, snatched: nil, hit_and_runs: nil,
        user_class: nil, uploads: nil, forum_posts: nil, torrent_comments: nil)
      ProfileClaim.new(site:, external_user_id: user_id, profile_code: ProfileClaim.generate_code, external_username: stats.external_username,
        stats:, checked_at: Time.current)
    end
end
