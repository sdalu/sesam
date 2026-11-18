# frozen_string_literal: true

require "test_helper"

# Users in the database: names, invitations spent once, keys kept as
# digests, and what goes with a user removed (passwords:
# UserPasswordsTest).
class UsersTest < Minitest::Test
    Users = Sesam::Users
    NOW = Time.new(2026, 11, 15, 10, 0)

    def setup
        @db = Sequel.sqlite
        Sesam.migrate(@db)
        @users = Users.new(@db, reserved: %w[root])
        @users.add("alice", now: NOW)
    end

    # Taken whatever its case, as a reserved name is; reserved as a
    # configuration may write them, symbols too.
    def test_names_malformed_taken_or_reserved_are_refused
        ["al ice", "", "-x", "x" * 33, "alice", "Alice", "Root"].each do |name|
            assert_raises(Users::Error, name) { @users.add(name) }
        end
        assert_raises(Users::Error) do
            Users.new(@db, reserved: %i[system]).add("System")
        end
        assert_equal "root", Users.new(@db).add("root")
    end

    def test_an_invitation_is_spent_once
        token = @users.invite("alice", now: NOW)
        assert_equal "alice", @users.invitation(token, now: NOW).user
        assert_equal "alice", @users.redeem(token, now: NOW)
        assert_nil @users.redeem(token, now: NOW)
        assert_nil @users.invitation(token, now: NOW)
    end

    def test_an_invitation_lapses
        token = @users.invite("alice", seconds: 60, now: NOW)
        assert_nil @users.redeem(token, now: NOW + 61)
    end

    # Only the newest link works.
    def test_a_new_invitation_withdraws_the_open_one
        old = @users.invite("alice", now: NOW)
        new = @users.invite("alice", now: NOW)
        assert_nil @users.invitation(old, now: NOW)
        refute_nil @users.invitation(new, now: NOW)
    end

    # What the block refuses (a password too short) leaves the
    # invitation open and no password set.
    def test_a_refusal_in_the_redemption_keeps_the_invitation
        token = @users.invite("alice", now: NOW)
        assert_raises(Users::Error) do
            @users.redeem(token, now: NOW) { @users.password!(it, "short") }
        end
        refute @users.password?("alice")
        refute_nil @users.invitation(token, now: NOW)
    end

    # An invitation's token is kept as its digest only.
    def test_an_invitation_is_kept_as_a_digest
        token = @users.invite("alice", now: NOW)
        refute_includes @db[:invites].select_map(:digest), token
    end

    def test_a_key_is_shown_once_and_kept_as_a_digest
        key = @users.key("alice", label: "script", now: NOW)
        assert_equal "alice", @users.key_owner(key)
        refute_includes @db[:user_keys].select_map(:digest), key
        id = @users.keys_of("alice").first.id
        @users.unkey("alice", id)
        assert_nil @users.key_owner(key)
        assert_raises(Users::Error) { @users.unkey("alice", id) }
        assert_raises(Users::Error) { @users.unkey("alice", "one") }
    end

    # Keys, invitations, addresses and passkeys go with their user.
    def test_a_user_removed_takes_their_ways_in_along
        key = @users.key("alice")
        @users.invite("alice")
        @users.address!("alice", "192.0.2.7")
        Sesam::Passkeys.new(@db).add("alice", id: "c1", public_key: "pk",
                                              sign_count: 0, label: "phone")
        @users.remove("alice")
        assert_nil @users.key_owner(key)
        counts = %i[invites user_addresses passkeys].map { @db[it].count }
        assert_equal [0, 0, 0], counts
    end

    def test_a_listing_says_each_way_in
        @users.password!("alice", "a long enough password")
        @users.key("alice")
        @users.address!("alice", "192.0.2.7")
        row = @users.list(now: NOW).first
        assert_equal ["alice", true, 1, 0, ["192.0.2.7"]],
                     row.to_h.values_at(:name, :password, :keys, :passkeys,
                                        :addresses)
    end

    # A LAN address names one user, never loopback nor a network.
    def test_an_address_names_one_user
        @users.add("bob")
        @users.address!("alice", "192.0.2.7")
        @users.address!("bob", "192.0.2.7")
        assert_equal "bob", @users.address_owner("192.0.2.7")
        ["127.0.0.1", "::1", "192.0.2.0/24", "nowhere"].each do |bad|
            assert_raises(Users::Error, bad) { @users.address!("bob", bad) }
        end
        assert_nil @users.address_owner("nowhere")
    end

    # A name removed then added again holds none of the old sessions.
    def test_a_user_added_again_keeps_none_of_the_old_sessions
        @users.remove("alice")
        @users.add("alice", now: NOW + 60)
        refute @users.session_valid?("alice", ms(NOW + 30))
        assert @users.session_valid?("alice", ms(NOW + 61))
        refute @users.session_valid?("carol", ms(NOW + 61))
    end

    # A session given earlier in the very second sessions end, ends.
    def test_a_sign_out_ends_a_session_of_the_same_second
        @users.end_sessions!("alice", now: NOW + 0.9)
        refute @users.session_valid?("alice", ms(NOW + 0.1))
        assert @users.session_valid?("alice", ms(NOW + 0.95))
    end

    private

    def ms(time) = Sesam::Stamp.ms(time)
end
