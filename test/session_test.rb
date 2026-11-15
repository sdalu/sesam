# frozen_string_literal: true

require "base64"

require "test_helper"

# A browser's session: a name signed with an expiry, no secret in it,
# scoped to the application's mount, under the cookie names the
# application gives.
class SessionTest < Minitest::Test
    Session = Sesam::Session
    SECRET = "s" * 40
    AT = Time.at(1_800_000_000)

    # What ClimatControl's sessions were before sesam: the same bytes,
    # so that nobody is signed out by the move.
    ALICE = "YWxpY2U6MTgwMDAwMDAwMDAwMCAxODAwMDAzNjAw." \
            "HrX_ZjHQmBZBxUbcL_6wAgRcmgn4QIeFE4FLFz-P6Ag"
    ABC = "YWJjIDE4MDAwMDAzMDA.CMzL82a3VBCEGWu57rRzzMHB1X9YUNFfru9clJnYyqE"

    def session(lifetime = 3600, **)
        Session.new(SECRET, lifetime:, **)
    end

    def env(value, name = "sesam_session")
        { "HTTP_COOKIE" => "#{name}=#{value}" }
    end

    def test_the_stamp_is_byte_for_byte_what_it_was
        assert_equal ALICE, session.cookie_for("alice", "/a", now: AT)[:value]
        assert_equal ABC, session.challenge_cookie("abc", "/", now: AT)[:value]
        held = session.held_from(env(ALICE), now: AT + 60)
        assert_equal ["alice", 1_800_000_000_000], held.to_h.values
    end

    def test_a_session_says_its_name
        value = session.cookie_for("alice", "/a")[:value]
        assert_equal "alice", session.name_from(env(value))
    end

    def test_the_cookie_names_are_the_application_s
        named = session(cookie: "app_session", ceremony: "app_ceremony")
        value = named.cookie_for("alice", "/")[:value]
        assert_equal "alice", named.name_from(env(value, "app_session"))
        assert_nil named.name_from(env(value))
        challenge = named.challenge_cookie("abc", "/")[:value]
        assert_equal "abc",
                     named.challenge_from(env(challenge, "app_ceremony"))
    end

    def test_a_tampered_session_is_nobody
        mac = session.cookie_for("alice", "/")[:value].split(".").last
        assert_nil named("#{forged("bruno")}.#{mac}")
        assert_nil named(forged("alice"))
        assert_nil named("")
        assert_nil named("#{forged("alice")}.")
    end

    def test_another_secret_s_session_is_nobody
        value = session.cookie_for("alice", "/")[:value]
        other = Session.new("t" * 40, lifetime: 3600)
        assert_nil other.name_from(env(value))
    end

    def test_an_expired_session_is_nobody
        value = session(60).cookie_for("alice", "/")[:value]
        assert_nil session.name_from(env(value), now: Time.now + 61)
    end

    def test_the_cookie_is_confined_to_the_mount
        cookie = session.cookie_for("alice", "/a")
        assert_equal "/a", cookie[:path]
        assert cookie[:secure]
        assert cookie[:httponly]
        assert_equal :lax, cookie[:same_site]
        assert_equal "/", session.cookie_for("alice", "")[:path]
    end

    # A ceremony's challenge, signed for minutes, and only as signed.
    def test_a_challenge_comes_back_for_minutes
        value = session.challenge_cookie("abc", "/")[:value]
        ceremony = env(value, "sesam_ceremony")
        assert_equal "abc", session.challenge_from(ceremony)
        assert_nil session.challenge_from(ceremony, now: Time.now + 301)
        assert_nil session.challenge_from(env("abc", "sesam_ceremony"))
    end

    def test_forgetting_keeps_the_path
        gone = session.forget("/a")
        assert_equal ["", 0, "/a"], gone.values_at(:value, :max_age, :path)
    end

    private

    def named(value) = session.name_from(env(value))

    def forged(name)
        Base64.urlsafe_encode64("#{name} #{Time.now.to_i + 99}",
                                padding: false)
    end
end
