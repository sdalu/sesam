# frozen_string_literal: true

require "json_store_support"

# JsonStore's transactions: all or nothing, joined when nested, and
# serialised across processes.
class JsonStoreTransactionsTest < Minitest::Test
    include JsonStoreSupport

    def test_exception_leaves_the_file_byte_identical
        @store.insert(:users, { name: "a" })
        before = File.binread(@path)
        assert_raises(RuntimeError) do
            @store.transaction do
                @store.insert(:users, { name: "b" })
                raise "boom"
            end
        end
        assert_equal before, File.binread(@path)
        assert_equal 1, @store.count(:users)
    end

    def test_rollback_keeps_nothing_and_returns_nil
        @store.insert(:users, { name: "a" })
        result = @store.transaction do
            @store.insert(:users, { name: "b" })
            @store.rollback!
        end
        assert_nil result
        assert_equal 1, @store.count(:users)
    end

    def test_transaction_returns_the_blocks_value
        assert_equal(42, @store.transaction { 42 })
    end

    def test_rollback_outside_a_transaction_raises
        assert_raises(Sesam::Error) { @store.rollback! }
    end

    def test_a_transaction_is_said_open_inside_only
        refute @store.in_transaction?
        assert(@store.transaction { @store.in_transaction? })
        refute @store.in_transaction?
    end

    # The inner transaction joins the outer: its write goes with it.
    def test_nested_transaction_joins_the_outer
        assert_raises(RuntimeError) do
            @store.transaction do
                @store.transaction { @store.insert(:users, { name: "in" }) }
                raise "boom"
            end
        end
        assert_equal 0, @store.count(:users)
    end

    # No savepoint: a rollback in the inner one undoes the outermost
    # whole, the outer's own earlier write included, and it returns nil.
    def test_rollback_in_a_nested_transaction_undoes_the_outermost
        result = @store.transaction do
            @store.insert(:users, { name: "outer" })
            @store.transaction do
                @store.insert(:users, { name: "inner" })
                @store.rollback!
            end
            :not_reached
        end
        assert_nil result
        assert_equal 0, @store.count(:users)
    end

    # Two processes, each with its own store, share one path.
    def test_two_processes_insert_at_once
        pids = Array.new(2) { fork_inserting(25) }
        codes = pids.map { Process.wait2(it).last.exitstatus }
        assert_equal [0, 0], codes
        keys = Sesam::JsonStore.new(@path).all(:user_keys)
        assert_equal 50, keys.size
        assert_equal 50, keys.map { it[:id] }.uniq.size
    end

    private

    def fork_inserting(count)
        Process.fork do
            store = Sesam::JsonStore.new(@path)
            count.times { store.insert(:user_keys, { user: "a" }) }
            exit!(0)
        rescue Exception # rubocop:disable Lint/RescueException
            exit!(1)
        end
    end
end
