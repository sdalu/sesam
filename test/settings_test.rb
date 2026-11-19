# frozen_string_literal: true

require "ipaddr"

require "test_helper"

# What an application tells sesam, refused when no gate could work
# with it.
class SettingsTest < Minitest::Test
    STORE = ->(&block) { block.call(TestStore.fresh) }

    def settings(**) = Sesam::Settings.new(store: STORE, **)

    def test_the_names_follow_the_application
        app = settings(app: "climat")
        assert_equal 'Bearer realm="climat"', app.realm
        assert_equal "X-Climat-Sign-In", app.sign_in_header
        assert_equal "climat.internal", app.internal
    end

    def test_networks_are_read_or_refused
        app = settings(lan: ["192.0.2.0/24"], proxies: ["127.0.0.1"])
        assert app.lan?("192.0.2.9")
        refute app.lan?("198.51.100.9")
        refute app.lan?("nowhere")
        assert app.proxy?("127.0.0.1")
        assert_raises(Sesam::Networks::Error) { settings(lan: ["x"]) }
    end

    # An IPAddr given keeps its mask (its to_s would not).
    def test_networks_given_as_addresses_keep_their_mask
        lan = Sesam::Networks.new([IPAddr.new("192.0.2.0/24")])
        assert settings(lan:).lan?("192.0.2.9")
        assert Sesam::Networks.new([IPAddr.new("192.0.2.0/24")])
                              .include?("192.0.2.200")
        refute lan.include?("192.0.3.1")
    end

    def test_an_unknown_setting_is_refused
        error = assert_raises(Sesam::Settings::Error) { settings(lna: []) }
        assert_match(/lna/, error.message)
    end

    # A store, or a callable yielding one; anything else refused.
    def test_a_store_is_a_store_or_a_callable
        store = Sesam::SequelStore.new(Sequel.sqlite)
        Sesam::Settings.new(store:).store { assert_same store, it }
        [1, "store", Object.new, Sequel.sqlite].each do |store|
            assert_raises(Sesam::Settings::Error) do
                Sesam::Settings.new(store:)
            end
        end
    end

    def test_what_is_accepted
        assert_equal %w[key passkey password], settings.accept.to_a
        assert_equal %w[password], settings(accept: %w[key password])
            .accept.sign_in
        [[], ["pin"], %w[key pin]].each do |given|
            assert_raises(Sesam::Accept::Error) { settings(accept: given) }
        end
    end

    # A passkey ends in a session: none to give, no passkey; passkeys
    # not accepted, none either.
    def test_a_passkey_wants_a_session_and_to_be_accepted
        passkey = Object.new
        assert_raises(Sesam::Settings::Error) { settings(passkey:) }
        session = Sesam::Session.new("s" * 40, lifetime: 60)
        assert_same passkey, settings(passkey:, session:).passkey
        assert_nil settings(passkey:, session:,
                            accept: %w[key password]).passkey
    end

    def test_a_reset_s_effect_and_recovery_are_checked
        assert_equal "keep", settings.reset_passkeys
        assert_raises(Sesam::Settings::Error) { settings(reset_passkeys: "all") }
        refute settings.recovery
        assert_equal 3600, settings(recovery: true).recovery_for
        assert_raises(Sesam::Settings::Error) { settings(recovery: "yes") }
    end
end
