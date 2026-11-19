# frozen_string_literal: true

require "test_helper"

# The store over the application's Sequel database: rows in and out as
# Hashes, transactions kept whole or not at all, a nested one joining
# the one around it.
class SequelStoreTest < Minitest::Test
    NOW = 1_763_387_446_640

    def setup
        db = Sequel.sqlite
        Sesam.migrate(db)
        @store = Sesam::SequelStore.new(db)
        @store.insert(:users, { name: "alice", created_at: NOW })
    end

    def test_only_a_sequel_database_is_wrapped
        assert_raises(Sesam::Error) { Sesam::SequelStore.new(Object.new) }
    end

    def test_rows_are_numbered_where_the_table_says
        assert_nil @store.insert(:users, { name: "bruno", created_at: NOW })
        first = key("one")
        assert_equal first + 1, key("two")
        ids = @store.all(:user_keys, order: [:id]).map { it[:id] }
        assert_equal [first, first + 1], ids
    end

    def test_a_rollback_outside_a_transaction_is_an_error
        assert_raises(Sesam::Error) { @store.rollback! }
    end

    def test_a_transaction_is_said_open_inside_only
        refute @store.in_transaction?
        assert(@store.transaction { @store.in_transaction? })
        refute @store.in_transaction?
    end

    def test_a_rollback_keeps_nothing_and_answers_nil
        got = @store.transaction do
            key("one")
            @store.rollback!
        end
        assert_nil got
        assert_equal 0, @store.count(:user_keys)
    end

    # The inner transaction done, a failure after it in the outer one
    # leaves none of the inner's work: they were one.
    def test_a_nested_transaction_joins
        assert_raises(RuntimeError) do
            @store.transaction do
                @store.transaction { key("inner") }
                raise "after the inner one"
            end
        end
        assert_equal 0, @store.count(:user_keys)
        joined = @store.transaction { @store.transaction { 1 } }
        assert_equal 1, joined
    end

    # A rollback! in a joined transaction undoes the outermost one: what
    # the outer block wrote before it is lost, and the outer answers nil.
    def test_a_rollback_in_a_joined_transaction_undoes_the_outermost
        got = @store.transaction do
            key("outer")
            @store.transaction { @store.rollback! }
            key("never")
        end
        assert_nil got
        assert_equal 0, @store.count(:user_keys)
    end

    def test_a_nil_sorts_first
        @store.insert(:users, { name: "bruno", created_at: NOW,
                                sessions_since: NOW })
        names = @store.all(:users, order: [:sessions_since]).map { it[:name] }
        assert_equal %w[alice bruno], names
    end

    def test_an_unknown_table_is_refused
        assert_raises(Sesam::Error) { @store.count(:sessions) }
        assert_raises(Sesam::Error) { @store.insert(:sessions, {}) }
    end

    private

    def key(digest)
        @store.insert(:user_keys, { user: "alice", digest:, created_at: NOW })
    end
end
