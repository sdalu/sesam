# frozen_string_literal: true

require "test_helper"

# Networks asked about one address: a network is none, nor counted as
# its first address once written out.
class NetworksTest < Minitest::Test
    def test_a_network_is_not_one_address
        lan = Sesam::Networks.new(["10.0.0.0/8", "2001:db8::/32"])
        refute lan.include?("10.0.0.0/8")
        refute lan.include?("2001:db8::/48")
        assert lan.include?("10.1.2.3")
        assert lan.include?("::ffff:10.1.2.3")
    end

    def test_a_network_is_written_as_given
        assert_equal "10.0.0.0/8", Sesam::Networks.canonical("10.0.0.0/8")
        assert_equal "10.1.2.3", Sesam::Networks.canonical("::ffff:10.1.2.3")
        assert_equal "unknown", Sesam::Networks.canonical("unknown")
    end
end
