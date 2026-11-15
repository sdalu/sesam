# frozen_string_literal: true

require "test_helper"

# Each user's passkeys: the public half by its credential id, found by
# its owner only.
class PasskeysTest < Minitest::Test
    def setup
        @db = Sequel.sqlite
        Sesam.migrate(@db)
        users = Sesam::Users.new(@db)
        users.add("alice")
        users.add("bob")
        @keys = Sesam::Passkeys.new(@db)
        @keys.add("alice", id: "c1", public_key: "pk", sign_count: 3,
                           label: "phone")
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
