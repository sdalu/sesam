# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require "test_helper"

# Two processes adding one name at once, on a file shared between them
# (a JsonStore, then SQLite on a file, whatever store the suite runs
# on: SQLite in memory cannot be shared): one is refused by
# Users::Error, one user kept.
class UsersRaceTest < Minitest::Test
    ROUNDS = 20

    def setup = @dir = Dir.mktmpdir("sesam-race")
    def teardown = FileUtils.remove_entry(@dir)

    def test_a_name_added_twice_at_once_is_kept_once
        ROUNDS.times do |round|
            path = File.join(@dir, "#{round}.json")
            assert_equal [0, 1], racing(path) { Sesam::JsonStore.new(path) }
            assert_equal 1, Sesam::JsonStore.new(path).count(:users)
        end
    end

    def test_on_sqlite_too
        ROUNDS.times do |round|
            path = File.join(@dir, "#{round}.db")
            Sequel.sqlite(path) { Sesam.migrate(it) }
            assert_equal [0, 1], racing(path) { sqlite(path) }
            assert_equal 1, Sequel.sqlite(path) { it[:users].count }
        end
    end

    private

    # Each process's exit, sorted: 0 added, 1 refused, 2 anything else;
    # both start together, each on the store the block opens.
    def racing(path, &)
        go = "#{path}.go"
        pids = Array.new(2) { fork { exit!(add_when(go, &)) } }
        File.write(go, "")
        pids.map { Process.wait2(it).last.exitstatus }.sort
    end

    def add_when(go)
        sleep 0.001 until File.exist?(go)
        Sesam::Users.new(yield).add("alice")
        0
    rescue Sesam::Users::Error
        1
    rescue StandardError
        2
    end

    def sqlite(path) = Sesam::SequelStore.new(Sequel.sqlite(path))
end
