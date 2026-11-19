# frozen_string_literal: true

require "fileutils"
require "tmpdir"

require "minitest/autorun"

require "sesam"

# The store the suite runs on, named by SESAM_STORE: `sequel` (the
# default) for a migrated SQLite in memory, `json` for a JsonStore in a
# directory removed once the suite has run. Rake runs the suite on each.
module TestStore
    KIND = ENV.fetch("SESAM_STORE", "sequel")
    raise "SESAM_STORE: sequel or json, not #{KIND}" unless
        %w[sequel json].include?(KIND)

    def self.fresh = KIND == "json" ? json : sequel

    def self.sequel
        db = Sequel.sqlite
        Sesam.migrate(db)
        Sesam::SequelStore.new(db)
    end

    def self.json
        dir = Dir.mktmpdir("sesam-test")
        Minitest.after_run { FileUtils.remove_entry(dir) }
        Sesam::JsonStore.new(File.join(dir, "store.json"))
    end
end
