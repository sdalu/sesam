# frozen_string_literal: true

require "test_helper"

# Each user's passkeys: the public half by its credential id, found by
# its owner only.
class PasskeysTest < Minitest::Test
    def setup
        @store = TestStore.fresh
        users = Sesam::Users.new(@store)
        users.add("alice")
        users.add("bob")
        @keys = Sesam::Passkeys.new(@store)
        @keys.add("alice", id: "c1", public_key: "pk", sign_count: 3,
                           label: "phone")
    end

    def test_a_passkey_is_dated_when_registered
        before = Sesam::Stamp.ms(Time.now)
        @keys.add("bob", id: "c2", public_key: "pk", sign_count: 0,
                         label: "laptop")
        dated = Sesam::Stamp.ms(@keys.find("bob", "c2").created_at)
        assert_includes before..Sesam::Stamp.ms(Time.now), dated
    end

    # None kept for a name no user has: a user added later under it
    # would inherit it.
    def test_a_passkey_for_no_user_is_refused
        assert_raises(Sesam::Passkeys::Error) do
            @keys.add("ghost", id: "c9", public_key: "pk", sign_count: 0,
                               label: "phone")
        end
        Sesam::Users.new(@store).add("ghost")
        assert_empty @keys.of("ghost")
    end

    def test_a_credential_is_its_owner_s
        assert_equal "alice", @keys.owner_of("c1")
        assert_nil @keys.find("bob", "c1")
        assert_equal ["phone"], @keys.of("alice").map(&:label)
        assert_empty @keys.remove("bob", "c1")
        assert_equal 1, @keys.of("alice").size
    end

    # Registered again by its owner, an id replaces its record.
    def test_registered_again_an_id_replaces_its_record
        @keys.add("alice", id: "c1", public_key: "pk2", sign_count: 0,
                           label: "tablet")
        assert_equal ["tablet"], @keys.of("alice").map(&:label)
    end

    def test_an_assertion_records_the_counter
        @keys.seen("alice", "c1", 7)
        assert_equal 7, @keys.find("alice", "c1").sign_count
    end

    # A credential id is one user's: another's registration is refused.
    def test_an_id_held_by_another_is_refused
        assert_raises(Sesam::Passkeys::Error) do
            @keys.add("bruno", id: "c1", public_key: "pk2", sign_count: 0,
                               label: "tablet")
        end
        assert_equal "alice", @keys.owner_of("c1")
    end

    # A database is given wrapped, as a store: bare, it is refused.
    def test_a_bare_database_is_refused
        error = assert_raises(Sesam::Error) do
            Sesam::Passkeys.new(Sequel.sqlite)
        end
        assert_match(/SequelStore/, error.message)
    end

    # A lost device's, all of a user's at once; others' kept.
    def test_clearing_a_user_s_passkeys
        @keys.add("alice", id: "c2", public_key: "pk", sign_count: 0,
                           label: "tablet")
        @keys.add("bob", id: "c3", public_key: "pk", sign_count: 0,
                         label: "phone")
        assert_equal 2, @keys.clear("alice")
        assert_empty @keys.of("alice")
        assert_equal ["c3"], @keys.of("bob").map(&:id)
    end
end
