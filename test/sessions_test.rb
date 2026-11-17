# frozen_string_literal: true

require "minitest/mock"

require "web_support"

# Becoming a user in a browser: an invitation read without being spent,
# then spent once with a password; a password changed only with the
# current one; and what the application is told.
class SessionsTest < Minitest::Test
    include WebSupport

    # Read, not spent: the page greets its user first.
    def test_an_invitation_read
        token = users.invite("alice")
        @profiles["alice"] = { first_name: "Alice" }
        assert_equal 200, call(:post, "/session/invite/check", { token: })
        assert_equal ["alice", false, "Alice", ORIGIN],
                     reply["data"].values_at("name", "password",
                                             "first_name", "origin")
        assert_equal 200, call(:post, "/session/invite/check", { token: })
    end

    # When it lapses, to the millisecond, its offset said (ISO 8601).
    def test_an_invitation_read_says_when_it_lapses
        token = users.invite("alice")
        call(:post, "/session/invite/check", { token: })
        assert_equal users.invitation(token).expires_at.xmlschema(3),
                     reply.dig("data", "expires_at")
    end

    # Spent once on a password, which signs no one in; the application
    # told in the transaction, then notified.
    # A profile never speaks for sesam: one naming a key of sesam's
    # own (a display name as `name`) is refused rather than shown.
    def test_a_profile_cannot_replace_sesam_s_keys
        token = users.invite("alice")
        @profiles["alice"] = { name: "Alice Dupont" }
        error = assert_raises(Sesam::Error) do
            call(:post, "/session/invite/check", { token: })
        end
        assert_match(/sesam_profile.*name/, error.message)
    end

    def test_an_invitation_spent_with_a_password
        token = users.invite("alice")
        assert_equal 200, call(:post, "/session/invite",
                               { token:, password: PASSWORD })
        assert_equal 401, call(:get, "/secret")
        assert_equal 404, call(:post, "/session/invite",
                               { token:, password: PASSWORD })
        assert_equal "token", reply["field"]
        call(:post, "/session/password", { name: "alice", password: PASSWORD })
        assert_equal 200, call(:get, "/secret")
    end

    def test_an_invitation_spent_is_told
        token = users.invite("alice")
        call(:post, "/session/invite", { token:, password: PASSWORD })
        assert_equal [[:changed, "alice", true],
                      [:notify, "alice", :password]], @told
    end

    # A reset ends the sessions given before it: a lost phone's too.
    def test_an_invitation_spent_ends_the_other_sessions
        signed_in_as_alice
        assert_equal 200, call(:get, "/secret")
        travel(1) do
            token = users.invite("alice")
            call(:post, "/session/invite", { token:, password: "z" * 12 })
            assert_equal 401, call(:get, "/secret")
        end
    end

    # Changed here, the password ends the other sessions, not this one.
    def test_a_password_changed_keeps_this_session
        signed_in_as_alice
        travel(1) do
            call(:put, "/session/password",
                 { current: PASSWORD, password: "z" * 12 })
            assert_equal 200, call(:get, "/secret")
            before = Sesam::Stamp.ms(Time.now) - 1000
            refute users.session_valid?("alice", before)
        end
        assert_equal [:notify, "alice", :password], @told.last
    end

    def test_a_password_changed_with_the_current_one
        signed_in_as_alice
        wrong = { current: "not the password", password: "x" * 12 }
        assert_equal 403, call(:put, "/session/password", wrong)
        assert_equal 422, call(:put, "/session/password",
                               { current: PASSWORD, password: "short" })
        assert_equal 200, call(:put, "/session/password",
                               { current: PASSWORD, password: "y" * 12 })
        assert users.password_match?("alice", "y" * 12)
    end

    # Looking tokens up is counted by address.
    def test_invitation_lookups_are_counted
        20.times { call(:post, "/session/invite/check", { token: "nope" }) }
        assert_equal 429, call(:post, "/session/invite/check",
                               { token: users.invite("alice") })
    end

    # A password refused keeps the invitation open, and tells nothing.
    def test_a_refused_password_keeps_the_invitation
        token = users.invite("alice")
        assert_equal 422, call(:post, "/session/invite",
                               { token:, password: "short" })
        assert_equal 200, call(:post, "/session/invite/check", { token: })
        assert_empty @told
    end

    # The LAN has no name to set a password for.
    def test_the_lan_has_no_password
        assert_equal 200, call(:get, "/session", peer: LAN)
        assert_equal({ "name" => "lan:#{LAN}", "via" => "lan",
                       "password" => false, "origin" => ORIGIN,
                       "sign_in" => %w[password passkey] }, reply["data"])
        assert_equal 403, call(:put, "/session/password",
                               { password: "y" * 12 }, peer: LAN)
    end

    def test_signing_out_drops_the_session
        signed_in_as_alice
        assert_equal 200, call(:delete, "/session")
        assert_equal 401, call(:get, "/secret")
    end

    # A password is text: anything else is refused, as an invitation does.
    def test_a_password_changed_to_no_text_is_refused
        signed_in_as_alice
        assert_equal 422, call(:put, "/session/password",
                               { current: PASSWORD,
                                 password: { "a" => 1_234_567 } })
        assert users.password_match?("alice", PASSWORD)
    end

    private

    # The clock a second on, as a session issued now and one after would
    # be told apart.
    def travel(seconds, &)
        later = Time.now + seconds
        Time.stub(:now, later, &)
    end
end
