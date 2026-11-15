# frozen_string_literal: true

require "web_support"

# The gate's decision, and the headers it must never believe.
class AccessTest < Minitest::Test
    include WebSupport

    def test_a_lan_peer_is_admitted_under_its_address
        found = access.caller_for(from(LAN))
        assert_equal [:lan, "lan:#{LAN}"], [found.verdict, found.name]
    end

    def test_a_wan_peer_is_refused
        assert_predicate access.caller_for(from(WAN)), :refused?
    end

    # 198.51.100.x was not listed: "private" and "mine" differ.
    def test_a_network_not_listed_is_not_the_lan
        refute access.allow?(from("198.51.100.42"))
    end

    def test_forwarded_headers_cannot_forge_a_lan_address
        env = from(WAN, "HTTP_X_FORWARDED_FOR" => LAN,
                        "HTTP_X_REAL_IP" => LAN,
                        "HTTP_FORWARDED" => "for=#{LAN}")
        assert_predicate access.caller_for(env), :refused?
    end

    def test_forwarded_for_cannot_revoke_a_lan_address
        env = from(LAN, "HTTP_X_FORWARDED_FOR" => WAN)
        assert_equal :lan, access.caller_for(env).verdict
    end

    def test_a_missing_or_malformed_peer_is_refused
        refute access.allow?({})
        refute access.allow?(from(""))
        refute access.allow?(from("#{LAN}, #{WAN}"))
        refute access.allow?(from("../../etc/passwd"))
    end

    def test_a_key_admits_and_names_its_user_anywhere
        found = access.caller_for(bearer(WAN, BRUNO))
        assert_equal [:credential, "bruno"], [found.verdict, found.name]
        assert_equal "alice", access.caller_for(bearer(LAN, ALICE)).name
    end

    def test_a_wrong_key_is_refused_off_the_lan
        assert_predicate access.caller_for(bearer(WAN, ALICE.succ)), :refused?
    end

    def test_a_key_is_not_read_where_keys_are_not_accepted
        refused = access(accept: %w[password]).caller_for(bearer(WAN, ALICE))
        assert_predicate refused, :refused?
    end

    def test_a_session_admits_while_its_user_exists
        env = from(WAN, **cookie_env("alice"))
        assert_equal "alice", access.caller_for(env).name
        users.remove("alice")
        assert_predicate access.caller_for(env), :refused?
    end

    def test_a_lan_address_names_its_user_off_the_lan_none
        users.address!("alice", LAN)
        users.address!("bruno", WAN)
        found = access.caller_for(from(LAN))
        assert_equal [:lan, "alice", "alice"], found.to_h.values
        assert_predicate access.caller_for(from(WAN)), :refused?
    end

    def test_the_app_asking_itself_is_admitted_under_its_name
        found = access.caller_for(from(WAN, "app.internal" => "warm"))
        assert_equal [:lan, "app:warm"], [found.verdict, found.name]
    end

    private

    def bearer(peer, key) = from(peer, "HTTP_AUTHORIZATION" => "Bearer #{key}")
end
