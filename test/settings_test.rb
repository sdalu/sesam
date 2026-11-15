# frozen_string_literal: true

require "test_helper"

# What an application tells sesam, refused when no gate could work
# with it.
class SettingsTest < Minitest::Test
    DB = ->(&block) { block.call(Sequel.sqlite) }

    def settings(**) = Sesam::Settings.new(database: DB, **)

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
        assert_raises(Sesam::Settings::Error) { settings(lan: ["x"]) }
    end

    def test_an_unknown_setting_is_refused
        error = assert_raises(Sesam::Settings::Error) { settings(lna: []) }
        assert_match(/lna/, error.message)
    end

    def test_a_database_is_a_callable
        assert_raises(Sesam::Settings::Error) { Sesam::Settings.new(database: 1) }
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
end
