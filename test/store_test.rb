# frozen_string_literal: true

require "test_helper"

# What every store answers alike, run on the suite's store (TestStore):
# the suite runs once per store.
class StoreTest < Minitest::Test
    def setup = @store = TestStore.fresh

    # A block left early (throw, return, break) keeps its writes, as
    # one that ends does.
    def test_a_transaction_left_early_keeps_its_writes
        catch(:out) do
            @store.transaction do
                add("thrown")
                throw :out
            end
        end
        left_by_return
        [1].each { @store.transaction { add("broken") || break } }
        names = @store.all(:users, order: [:name]).map { it[:name] }
        assert_equal %w[broken returned thrown], names
    end

    private

    def add(name) = @store.insert(:users, { name:, created_at: 0 })

    def left_by_return
        @store.transaction do
            add("returned")
            return
        end
    end
end
