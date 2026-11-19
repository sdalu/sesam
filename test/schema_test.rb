# frozen_string_literal: true

require "test_helper"

# sesam's tables, migrated with a version of their own: made where
# missing, left as they are where an application made them first, and
# never migrated down.
class SchemaTest < Minitest::Test
    T = Time.new(2026, 11, 15, 9, 0)

    # The column as MySQL describes it (SHOW FULL COLUMNS).
    PUBLIC_KEY = { Field: "public_key", Type: "varchar(255)", Null: "NO",
                   Default: nil, Key: "", Extra: "" }.freeze

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
        Sesam::Users.new(Sesam::SequelStore.new(db)).add("alice")
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

    # Where a String is varchar(255) (MySQL), an RSA passkey's public
    # key (363 characters at 2048 bits) would not fit: text there, its
    # NOT NULL kept. SQLite keeps any length, its table left as it is.
    def test_a_passkey_s_public_key_is_text
        mysql = Sequel.connect("mock://mysql", fetch: PUBLIC_KEY)
        migration("002").apply(mysql, :up)
        assert_includes mysql.sqls, "ALTER TABLE `passkeys` CHANGE COLUMN " \
                                    "`public_key` `public_key` text NOT NULL"
        sqlite = Sequel.sqlite
        Sesam.migrate(sqlite)
        assert_equal "varchar(255)", sqlite.schema(:passkeys).to_h
                                           .dig(:public_key, :db_type)
    end

    # ClimatControl's rows, its times read as the same moments in
    # milliseconds where nothing is set; a moment not yet come stays
    # missing.
    def test_times_become_milliseconds
        db = migrated_from_utc_times
        assert_equal [[ms(T), ms(T)]],
                     db[:users].select_map(%i[sessions_since created_at])
        assert_equal [[ms(T), ms(T + 60), nil]],
                     db[:invites].select_map(%i[created_at expires_at used_at])
    end

    def test_a_moment_left_out_is_refused
        db = migrated_from_utc_times
        assert_raises(Sequel::NotNullConstraintViolation) do
            db[:passkeys].insert(id: "c1", user: "alice", public_key: "pk",
                                 label: "phone")
        end
    end

    private

    def ms(time) = Sesam::Stamp.ms(time)

    # Version 2 written as ClimatControl writes it, keeping UTC, and
    # migrated there; returned with nothing set.
    def migrated_from_utc_times
        Sequel.database_timezone = :utc
        db = Sequel.sqlite
        Sequel::Migrator.run(db, Sesam::Schema::DIRECTORY,
                             target: 2, table: Sesam::Schema::TABLE)
        alice_invited(db)
        Sesam.migrate(db)
        db
    ensure
        Sequel.database_timezone = nil
    end

    def alice_invited(db)
        db[:users].insert(name: "alice", created_at: T, sessions_since: T)
        db[:invites].insert(user: "alice", digest: "d", created_at: T,
                            expires_at: T + 60)
    end

    # sesam's migration `number`, loaded on its own.
    def migration(number)
        load Dir[File.join(Sesam::Schema::DIRECTORY, "#{number}_*.rb")].first
        Sequel::Migration.descendants.last
    end

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
