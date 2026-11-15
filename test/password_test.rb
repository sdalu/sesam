# frozen_string_literal: true

require "test_helper"

# A password kept as an scrypt hash, its cost and salt beside it: checked
# in constant time, never kept in clear, and refused when too short.
class PasswordTest < Minitest::Test
    Password = Sesam::Password
    GIVEN = "a long enough password"

    # What ClimatControl kept before sesam existed: a hash made there
    # (salt sixteen 0x01 bytes) must still check here.
    KEPT = "scrypt$16384$8$1$AQEBAQEBAQEBAQEBAQEBAQ==$" \
           "fvgd++KWMrKEnSJmQQAPku9QVy8iYZLOAZQaTCU1a4s="

    def test_a_hash_kept_before_still_checks
        assert Password.match?(GIVEN, KEPT)
        refute Password.match?("a long enough passwore", KEPT)
    end

    def test_the_hash_names_its_cost_and_holds_no_password
        kept = Password.digest(GIVEN)
        assert_match(/\Ascrypt\$16384\$8\$1\$[^$]+\$[^$]+\z/, kept)
        refute_includes kept, "long enough"
        assert Password.match?(GIVEN, kept)
    end

    def test_two_hashes_of_one_password_differ
        refute_equal Password.digest(GIVEN), Password.digest(GIVEN)
    end

    # A cost other than today's still checks: it is read from the hash.
    def test_an_older_cost_still_checks
        kept = Password.digest(GIVEN, cost: { N: 2**10, r: 8, p: 1 })
        assert Password.match?(GIVEN, kept)
    end

    def test_nothing_kept_or_garbage_matches_nothing
        [nil, "", "bcrypt$x", "scrypt$n$8$1$AA==$AA==",
         "scrypt$16384$8$1$!!$AA=="].each do |kept|
            refute Password.match?(GIVEN, kept), kept.inspect
        end
    end

    def test_a_short_or_controlled_password_is_refused
        assert_match(/12 characters/, Password.refusal("short"))
        assert_match(/control/, Password.refusal("#{GIVEN}\n"))
        assert_nil Password.refusal(GIVEN)
    end
end
