# frozen_string_literal: true

require "test_helper"

# sesam's tables, migrated with a version of their own: made where
# missing, left as they are where an application made them first, and
# never migrated down.
class SchemaTest < Minitest::Test
    T = Time.new(2026, 11, 15, 9, 0)

    def test_a_new_database_gets_every_table
        db = Sequel.sqlite
        Sesam.migrate(db)
        assert_equal %i[invites passkeys user_addresses user_keys users],
                     (db.tables - [:sesam_schema]).sort
        assert_equal Sesam::Schema.latest, db[:sesam_schema].get(:version)
        assert_equal %i[name password sessions_since created_at],
                     db[:users].columns
    end

    # ClimatControl's tables, made before sesam with columns of its own
    # (a profile, then): kept as they are, rows included.
    def test_tables_made_before_are_kept
        db = made_before
        db[:users].insert(name: "alice", first_name: "Alice", created_at: T)
        Sesam.migrate(db)
        assert_equal "Alice", db[:users].get(:first_name)
        assert db.table_exists?(:passkeys)
    end

    def test_migrating_twice_changes_nothing
        db = Sequel.sqlite
        Sesam.migrate(db)
        Sesam::Users.new(db).add("alice")
        Sesam.migrate(db)
        assert_equal ["alice"], db[:users].select_map(:name)
    end

    def test_a_newer_database_is_refused
        db = Sequel.sqlite
        Sesam.migrate(db)
        db[:sesam_schema].update(version: Sesam::Schema.latest + 1)
        assert_raises(Sesam::Schema::TooNew) { Sesam.migrate(db) }
        assert db.table_exists?(:users)
    end

    private

    # A database whose `users` an application made first, with a
    # column sesam does not know.
    def made_before
        Sequel.sqlite.tap do |db|
            db.create_table(:users) do
                String :name, primary_key: true
                String :first_name
                String :password
                Time :sessions_since
                Time :created_at, null: false
            end
        end
    end
end
