# frozen_string_literal: true

require "test_helper"

# A user's password: kept as an scrypt hash, matched in constant time,
# and removed, even when it is their last way in.
class UserPasswordsTest < Minitest::Test
    def setup
        @db = Sequel.sqlite
        Sesam.migrate(@db)
        @users = Sesam::Users.new(@db)
        @users.add("alice")
        @users.password!("alice", "a long enough password")
    end

    def test_passwords_are_kept_as_scrypt_hashes
        kept = @db[:users].where(name: "alice").get(:password)
        assert_match(/\Ascrypt\$16384\$8\$1\$/, kept)
        refute_includes kept, "long enough"
        assert @users.password_match?("alice", "a long enough password")
        refute @users.password_match?("alice", "a long enough passwore")
        refute @users.password_match?("carol", "a long enough password")
    end

    # Removed, even with no other way in, a password matches nothing.
    def test_a_password_removed_matches_nothing
        @users.unpassword!("alice")
        refute @users.password?("alice")
        refute @users.password_match?("alice", "a long enough password")
        assert_raises(Sesam::Users::Error) { @users.unpassword!("carol") }
    end
end
