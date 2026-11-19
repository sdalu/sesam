# frozen_string_literal: true

require "minitest/mock"

require "json_store_support"

# JsonStore's file: its mode, its version, what it refuses, and the
# writes that leave it whole.
class JsonStoreFileTest < Minitest::Test
    include JsonStoreSupport

    # Refused before anything is written, the store usable after.
    def test_text_json_cannot_hold_is_refused_unwritten
        @store.insert(:users, { name: "a" })
        before = File.binread(@path)
        assert_raises(Sesam::Error) do
            @store.insert(:users, { name: "caf\xE9" })
        end
        assert_equal before, File.binread(@path)
        assert_equal 1, @store.count(:users)
    end

    # Written to the link's target, the link kept, and the same lock
    # for both spellings.
    def test_a_symlinked_path_writes_its_target
        link = File.join(@dir, "link.json")
        File.symlink(@path, link)
        Sesam::JsonStore.new(link).insert(:users, { name: "a" })
        @store.insert(:users, { name: "b" })
        assert File.symlink?(link)
        assert_equal 2, Sesam::JsonStore.new(link).count(:users)
        refute_path_exists "#{link}.lock"
    end

    def test_a_new_file_is_private
        @store.insert(:users, { name: "a" })
        assert_equal 0o600, File.stat(@path).mode & 0o777
    end

    def test_a_rewrite_keeps_the_mode
        @store.insert(:users, { name: "a" })
        File.chmod(0o640, @path)
        @store.insert(:users, { name: "b" })
        assert_equal 0o640, File.stat(@path).mode & 0o777
    end

    def test_a_newer_document_raises_too_new
        File.write(@path, JSON.generate({ sesam: 2 }))
        assert_raises(Sesam::Schema::TooNew) { @store.count(:users) }
    end

    # Not a JSON object of the document's shape: refused, path named.
    def test_a_foreign_file_raises_error_naming_the_path
        ["not json", "[1, 2]", "{}", '{"sesam": 1}'].each do |content|
            File.write(@path, content)
            error = assert_raises(Sesam::Error) { @store.count(:users) }
            assert_includes error.message, @path
        end
    end

    def test_an_absent_file_reads_empty_and_stays_absent
        assert_equal [], @store.all(:users)
        assert_nil @store.first(:users)
        assert_equal 0, @store.count(:invites)
        refute_path_exists @path
    end

    # A read leaves the file as it was: same inode, same mtime.
    def test_a_read_does_not_rewrite_the_file
        @store.insert(:users, { name: "a" })
        File.utime(Time.at(1_000_000), Time.at(1_000_000), @path)
        before = File.stat(@path)
        read_everything
        after = File.stat(@path)
        assert_equal before.ino, after.ino
        assert_equal before.mtime, after.mtime
    end

    # A write that dies at the rename leaves the old document whole
    # and no temp file beside it.
    def test_an_interrupted_write_leaves_the_old_document_whole
        @store.insert(:users, { name: "a" })
        before = File.binread(@path)
        File.stub(:rename, ->(*) { raise IOError, "disk gone" }) do
            assert_raises(IOError) { @store.insert(:users, { name: "b" }) }
        end
        assert_equal before, File.binread(@path)
        assert_equal 1, @store.count(:users)
        assert_empty(Dir.children(@dir).grep(/\.tmp\z/))
    end

    private

    def read_everything
        @store.all(:users)
        @store.first(:users, name: "a")
        @store.count(:users)
    end
end
