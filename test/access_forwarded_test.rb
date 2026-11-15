# frozen_string_literal: true

require "web_support"

# The gate behind proxies: the socket peer a local proxy (127.0.0.1),
# an outer one on the LAN (192.0.2.5), both trusted to say whom they
# forward in Forwarded. The caller is the hop nearest the right that is
# no proxy: a LAN phone through the local proxy is the LAN; anyone
# through the outer proxy is not, whatever they write to the left; a
# chain of proxies alone, a hop naming no address, or a header from an
# untrusted peer admits nothing. X-Forwarded-For is never read.
class AccessForwardedTest < Minitest::Test
    include WebSupport

    LOCAL  = "127.0.0.1"
    OUTER  = "192.0.2.5"
    PHONE  = "192.0.2.21"
    REMOTE = "203.0.113.7"

    def access = super(lan: ["192.0.2.0/24"], proxies: [LOCAL, OUTER])

    def test_a_lan_phone_through_the_local_proxy_is_the_lan
        found = through("for=#{PHONE};proto=http")
        assert_equal [:lan, "lan:#{PHONE}"], [found.verdict, found.name]
    end

    def test_a_caller_through_the_outer_proxy_is_not
        assert_predicate through("for=#{REMOTE}", "for=#{OUTER}"), :refused?
    end

    def test_a_lan_address_written_to_the_left_changes_nothing
        assert_predicate through("for=#{PHONE}", "for=#{REMOTE}",
                                 "for=#{OUTER}"), :refused?
    end

    def test_a_chain_of_proxies_alone_admits_nothing
        assert_predicate through("for=#{OUTER}"), :refused?
        assert_predicate access.caller_for(from(LOCAL)), :refused?
    end

    def test_a_hop_naming_no_address_admits_nothing
        assert_predicate through("for=unknown", "for=#{OUTER}"), :refused?
        assert_predicate through("proto=https", "for=#{OUTER}"), :refused?
    end

    # The client counted when every hop is a proxy: the leftmost.
    def test_an_exhausted_chain_gives_the_leftmost_hop
        env = from(LOCAL, "HTTP_FORWARDED" => "for=#{OUTER}, for=#{LOCAL}")
        assert_equal OUTER, access.client(env)
        assert_equal REMOTE,
                     access.client(from(LOCAL, "HTTP_FORWARDED" =>
                                               "for=#{REMOTE}, for=#{OUTER}"))
    end

    def test_x_forwarded_for_is_never_read
        env = from(LOCAL, "HTTP_X_FORWARDED_FOR" => PHONE)
        assert_predicate access.caller_for(env), :refused?
    end

    def test_an_untrusted_peer_s_header_is_not_read
        env = from(REMOTE, "HTTP_FORWARDED" => "for=#{PHONE}")
        assert_predicate access.caller_for(env), :refused?
    end

    private

    # A request from the local proxy bearing the hops given.
    def through(*hops)
        access.caller_for(from(LOCAL, "HTTP_FORWARDED" => hops.join(", ")))
    end
end
