# frozen_string_literal: true

require "test_helper"

# A user removed by Users itself, whatever the store does on its own;
# a user named by a Symbol; and Users given a database bare, which it
# refuses.
class UsersRemovalTest < Minitest::Test
    Users = Sesam::Users
    OWNED = %i[user_keys invites user_addresses passkeys].freeze

    # Taken by Users itself, not left to the store: where nothing
    # cascades, nothing of alice's is left either.
    def test_a_user_removed_takes_their_rows_where_nothing_cascades
        db = Sequel.sqlite(foreign_keys: false)
        Sesam.migrate(db)
        store = Sesam::SequelStore.new(db)
        users = Users.new(store)
        users.add("alice")
        every_way_in(users, store)
        users.remove("alice")
        assert_equal [0] * 5, OWNED.map { store.count(it, user: "alice") } +
                              [store.count(:users)]
    end

    # A name given as a Symbol is its String: removing, ending the
    # sessions of or unsetting the password of :alice is alice's.
    def test_a_symbol_name_is_its_string
        users = Users.new(TestStore.fresh)
        users.add("alice")
        users.password!(:alice, "a long enough password")
        users.unpassword!(:alice)
        refute users.password?(:alice)
        users.end_sessions!(:alice, now: Time.at(2000))
        refute users.session_valid?("alice", 1_000_000)
        users.remove(:alice)
        refute users.exists?("alice")
    end

    # A database is given wrapped, as a store: bare, it is refused.
    def test_a_bare_database_is_refused
        error = assert_raises(Sesam::Error) { Users.new(Sequel.sqlite) }
        assert_match(/SequelStore/, error.message)
    end

    private

    # A key, an invitation, an address and a passkey for alice.
    def every_way_in(users, store)
        users.key("alice")
        users.invite("alice")
        users.address!("alice", "192.0.2.7")
        Sesam::Passkeys.new(store).add("alice", id: "c1", public_key: "pk",
                                                sign_count: 0, label: "phone")
    end
end
