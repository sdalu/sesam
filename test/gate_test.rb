# frozen_string_literal: true

require "web_support"

# The gate as a caller meets it, through an application: the LAN in,
# the WAN refused with a JSON 401 saying the ways past it, a key or a
# session admitting, failures counted.
class GateTest < Minitest::Test
    include WebSupport

    def test_a_lan_peer_is_admitted
        assert_equal 200, call(:get, "/secret", peer: LAN)
        assert_equal "lan:#{LAN}", reply.dig("data", "who")
    end

    def test_a_wan_peer_is_refused_with_the_ways_in
        assert_equal 401, call(:get, "/secret")
        assert_match(/Bearer/, reply["error"])
        assert_equal 'Bearer realm="app"',
                     last_response.headers["WWW-Authenticate"]
        assert_equal "password passkey",
                     last_response.headers["X-App-Sign-In"]
    end

    # Keys alone: no browser signs in, and the header says none.
    def test_the_ways_in_are_those_accepted
        @given = { accept: %w[key] }
        call(:get, "/secret")
        assert_equal "", last_response.headers["X-App-Sign-In"]
    end

    def test_a_key_admits_a_wan_peer
        assert_equal 200, call(:get, "/secret",
                               "HTTP_AUTHORIZATION" => "Bearer #{ALICE}")
        assert_equal "alice", reply.dig("data", "who")
    end

    # The session is set for the mount, Secure and HttpOnly, and holds
    # the name, never the password.
    def test_a_password_signs_in_for_the_mount
        @given = { mount: "/app" }
        assert_equal 200, signed_in_as_alice
        cookie = last_response.headers["Set-Cookie"]
        assert_match(%r{\Asesam_session=.*path=/app;.*secure.*httponly}i,
                     cookie)
        refute_includes cookie, "long"
    end

    # Wrong, or no such user: one answer; five failures, and the name
    # waits, the right password too.
    def test_failed_passwords_are_counted
        users.password!("alice", PASSWORD)
        assert_equal 403, sign_in("wrong password!!")
        assert_equal 403, sign_in(PASSWORD, name: "carol")
        4.times { sign_in("wrong password!!") }
        assert_equal 429, sign_in(PASSWORD)
    end

    # Counted by name and address together: a guesser elsewhere does not
    # keep alice out.
    def test_a_name_is_never_locked_out_from_everywhere
        users.password!("alice", PASSWORD)
        5.times { sign_in("wrong password!!") }
        assert_equal 429, sign_in(PASSWORD)
        assert_equal 200, sign_in(PASSWORD, peer: "198.51.100.9")
    end

    def test_passwords_not_accepted_are_not_offered
        @given = { accept: %w[key passkey] }
        users.password!("alice", PASSWORD)
        assert_equal 404, sign_in(PASSWORD)
        assert_equal "passwords are not offered here", reply["error"]
    end

    private

    def sign_in(password, name: "alice", peer: WAN)
        call(:post, "/session/password", { name:, password: }, peer:)
    end
end
