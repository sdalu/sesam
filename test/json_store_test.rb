# frozen_string_literal: true

require "json_store_support"

# JsonStore driven directly: the table operations of the store interface.
class JsonStoreTest < Minitest::Test
    include JsonStoreSupport

    # Each table takes rows in, hands them out, changes and drops them.
    def test_round_trip_on_each_table
        Sesam::JsonStore::TABLES.each do |table|
            @store.insert(table, { name: "b", rank: 1 })
            @store.insert(table, { name: "a", rank: 2 })
            @store.insert(table, { name: "c", rank: nil })
            assert_listing(table)
            assert_changes(table)
        end
    end

    # Several columns sort in the order given.
    def test_order_by_several_columns
        [[1, "b"], [2, "a"], [1, "a"]].each do |rank, name|
            @store.insert(:users, { name:, rank: })
        end
        rows = @store.all(:users, order: %i[rank name])
        assert_equal([[1, "a"], [1, "b"], [2, "a"]],
                     rows.map { [it[:rank], it[:name]] })
    end

    def test_order_puts_nil_before_any_value
        [2, nil, 1].each { @store.insert(:users, { rank: it }) }
        ranks = @store.all(:users, order: [:rank]).map { it[:rank] }
        assert_equal [nil, 1, 2], ranks
    end

    def test_nil_matches_a_missing_column
        @store.insert(:users, { name: "a" })
        @store.insert(:users, { name: "b", note: "x" })
        assert_equal 1, @store.count(:users, note: nil)
        assert_equal "a", @store.first(:users, note: nil)[:name]
    end

    # An id is the store's, up and never back, even past a delete.
    def test_ids_increase_and_are_not_reused
        %i[user_keys invites].each do |table|
            ids = Array.new(3) { @store.insert(table, { user: "a" }) }
            assert_equal ids.sort, ids
            assert_equal 3, ids.uniq.size
            @store.delete(table, id: ids.last)
            assert_operator @store.insert(table, { user: "a" }), :>, ids.last
        end
    end

    def test_other_tables_give_no_id
        assert_nil @store.insert(:users, { name: "a" })
    end

    def test_a_caller_given_id_is_overwritten
        id = @store.insert(:invites, { id: 99, user: "a" })
        assert_equal id, @store.first(:invites)[:id]
    end

    def test_an_unknown_table_raises_error
        assert_raises(Sesam::Error) { @store.count(:nope) }
    end

    private

    def assert_listing(table)
        names = @store.all(table, order: [:name]).map { it[:name] }
        assert_equal %w[a b c], names
        assert_equal 3, @store.count(table)
        assert_equal "a", @store.first(table, rank: 2)[:name]
        assert_equal(["c"], @store.all(table, rank: nil).map { it[:name] })
    end

    def assert_changes(table)
        assert_equal 1, @store.update(table, { name: "z" }, rank: 2)
        assert_equal "z", @store.first(table, rank: 2)[:name]
        assert_equal 1, @store.delete(table, rank: nil)
        assert_equal 1, @store.delete(table, rank: 1)
        assert_equal 1, @store.count(table)
    end
end
