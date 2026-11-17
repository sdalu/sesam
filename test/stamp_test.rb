# frozen_string_literal: true

require "test_helper"

# A moment sesam keeps reads the same in every process, whatever
# Sequel timezone each one sets: the host's, or none. Local time an
# hour off UTC, as the two settings read a time apart only there.
class StampTest < Minitest::Test
    NOW = Time.at(1_763_387_446_640_935r / 1_000_000)

    def setup
        @tz = ENV.fetch("TZ", nil)
        ENV["TZ"] = "Europe/Paris"
    end

    def teardown
        ENV["TZ"] = @tz
        Sequel.database_timezone = nil
        Sequel.application_timezone = nil
    end

    def test_a_moment_is_whole_milliseconds
        assert_equal 1_763_387_446_640, Sesam::Stamp.ms(NOW)
        assert_equal Time.at(1_763_387_446_640r / 1000),
                     Sesam::Stamp.time(1_763_387_446_640)
        assert_nil Sesam::Stamp.time(nil)
    end

    # Written where the host keeps UTC, read where nothing is set (a
    # console, a script): the same moment, not one shifted by the
    # offset.
    def test_a_passkey_reads_the_same_without_the_writer_s_setting
        before = Sesam::Stamp.ms(Time.now)
        keys = written_keeping_utc
        after = Sesam::Stamp.ms(Time.now)
        Sequel.database_timezone = nil
        Sequel.application_timezone = nil
        assert_includes before..after,
                        Sesam::Stamp.ms(keys.of("alice").first.created_at)
    end

    private

    # Alice's passkey, written as ClimatControl sets Sequel.
    def written_keeping_utc
        db = Sequel.sqlite
        Sesam.migrate(db)
        Sequel.database_timezone = :utc
        Sequel.application_timezone = :local
        Sesam::Users.new(db).add("alice", now: NOW)
        Sesam::Passkeys.new(db).tap do |keys|
            keys.add("alice", id: "c1", public_key: "pk", sign_count: 0,
                              label: "phone")
        end
    end
end
