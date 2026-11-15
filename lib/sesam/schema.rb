# frozen_string_literal: true

require "sequel"

module Sesam
    # sesam's tables in the application's database, migrated by
    # Sesam.migrate with a version of their own (`sesam_schema`), apart
    # from the application's migrations: the application runs this one
    # first, its own tables (a profile keyed by the user) pointing at
    # sesam's.
    module Schema
        Sequel.extension :migration

        DIRECTORY = File.expand_path("migrations", __dir__)
        TABLE = :sesam_schema

        # A database whose sesam tables are newer than this sesam.
        class TooNew < Sesam::Error; end

        # The newest migration this sesam carries.
        def self.latest
            Dir.children(DIRECTORY).filter_map do |file|
                file[/\A(\d+)_\w+\.rb\z/, 1]&.to_i
            end.max
        end

        # The version `db` is at, 0 before any migration.
        def self.version(db)
            return 0 unless db.table_exists?(TABLE)
            db[TABLE].get(:version).to_i
        end
    end

    # Migrates `db`'s sesam tables to this sesam's newest; TooNew for a
    # database past it, never migrated down nor read as if older.
    def self.migrate(db)
        current = Schema.version(db)
        latest = Schema.latest
        if current > latest
            raise Schema::TooNew, "sesam's tables are at #{current}, this " \
                                  "sesam knows up to #{latest}: update it"
        end
        Sequel::Migrator.run(db, Schema::DIRECTORY, target: latest,
                                                    table: Schema::TABLE)
    end
end
