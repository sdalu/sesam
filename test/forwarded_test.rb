# frozen_string_literal: true

require "test_helper"

# The Forwarded header's hops, each reduced to the address it names.
class ForwardedTest < Minitest::Test
    def test_the_header_s_forms
        fors = Sesam::Forwarded.fors(
            "for=192.0.2.60;proto=http;by=203.0.113.43, " \
            "For=\"[2001:db8:cafe::17]:4711\", for=\"192.0.2.61:8080\", " \
            "for=unknown, proto=https"
        )
        assert_equal ["192.0.2.60", "2001:db8:cafe::17", "192.0.2.61",
                      "unknown", ""], fors
    end

    def test_no_header_is_no_hop
        assert_empty Sesam::Forwarded.fors(nil)
    end

    # An IPv6 address unbracketed keeps every colon: no port to take off.
    def test_a_bare_ipv6_is_kept_whole
        assert_equal ["2001:db8::1"], Sesam::Forwarded.fors("for=2001:db8::1")
    end
end
