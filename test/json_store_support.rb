# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require "test_helper"
require "sesam/json_store"

# A JsonStore on a file in a directory of its own, removed after.
module JsonStoreSupport
    def setup
        @dir = Dir.mktmpdir("sesam-json-store")
        @path = File.join(@dir, "store.json")
        @store = Sesam::JsonStore.new(@path)
    end

    def teardown
        FileUtils.remove_entry(@dir)
    end
end
