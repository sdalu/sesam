# frozen_string_literal: true

require "web_support"

# Behind a proxy every caller is the proxy: failures are counted by the
# client the trusted proxies forwarded (Forwarded's `for`, read from
# the right past each of them), so that one guesser does not lock every
# user out.
class ThrottleProxyTest < Minitest::Test
    include WebSupport

    PROXY = "127.0.0.1"
    OUTER = "192.0.2.99"

    def setup
        super
        @given = { lan: [], proxies: [PROXY, OUTER] }
    end

    def test_a_guesser_does_not_lock_others_out
        users.password!("bruno", PASSWORD)
        20.times { sign_in("user#{it}", "wrong password!", "203.0.113.7") }
        assert_equal 429, sign_in("bruno", PASSWORD, "203.0.113.7")
        assert_equal 200, sign_in("bruno", PASSWORD, "203.0.113.8")
    end

    # What a client writes to the left changes nothing.
    def test_the_client_is_read_past_the_trusted_proxies
        users.password!("alice", PASSWORD)
        5.times do |i|
            sign_in("alice", "wrong password!",
                    "198.51.100.#{i}, 203.0.113.7, #{OUTER}")
        end
        assert_equal 429, sign_in("alice", PASSWORD, "203.0.113.7, #{OUTER}")
        assert_equal 200, sign_in("alice", PASSWORD, "203.0.113.8, #{OUTER}")
    end

    # From a peer that is no trusted proxy, the header is not read.
    def test_an_untrusted_peer_s_header_is_not_read
        users.password!("alice", PASSWORD)
        5.times do |i|
            call(:post, "/session/password",
                 { name: "alice", password: "wrong password!" },
                 "HTTP_FORWARDED" => "for=203.0.113.#{i}")
        end
        assert_equal 429, call(:post, "/session/password",
                               { name: "alice", password: PASSWORD })
    end

    private

    def sign_in(name, password, forwarded)
        hops = forwarded.split(",").map { "for=#{it.strip}" }.join(", ")
        call(:post, "/session/password", { name:, password: },
             peer: PROXY, "HTTP_FORWARDED" => hops)
    end
end
