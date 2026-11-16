# frozen_string_literal: true

require "test_helper"
require "open3"

require "sesam/passkey"
# fake_client reaches for Forwardable without requiring it.
require "forwardable"
require "webauthn/fake_client"

# The two ceremonies against WebAuthn's own fake authenticator: it holds
# a key pair and signs as hardware would, so what runs here is the real
# relying party's real signature check. The refusals are the point: a
# signature that verifies proves an authenticator answered, not that
# this deployment trusts it, that it answered our challenge, or that it
# spoke to us.
# One ceremony's refusals read best together, past the class limit.
class PasskeyTest < Minitest::Test # rubocop:disable Metrics/ClassLength
    Passkey = Sesam::Passkey
    ORIGIN = "https://app.example.org"

    def setup
        @db = Sequel.sqlite
        Sesam.migrate(@db)
        @users = Sesam::Users.new(@db)
        %w[alice bruno].each { @users.add(it) }
        @keys = Sesam::Passkeys.new(@db)
        @passkey = Passkey.new(ORIGIN)
        @authenticator = WebAuthn::FakeAuthenticator.new
        @client = WebAuthn::FakeClient.new(ORIGIN,
                                           authenticator: @authenticator)
    end

    # What the browser's address bar says: https and a host, or localhost.
    def test_the_origin
        assert_equal ORIGIN, Passkey.origin!("#{ORIGIN}/")
        assert_equal "http://localhost:4580",
                     Passkey.origin!("http://localhost:4580")
        assert_equal ORIGIN, @passkey.origin
    end

    # Refused: plain http but on localhost, a path, no scheme, none.
    def test_an_origin_refused
        ["http://app.example.org", "https://h.example.org/app",
         "app.example.org", "", nil].each do |bad|
            assert_raises(Passkey::Error, bad.inspect) { Passkey.new(bad) }
        end
    end

    # ClimatControl's handles, derived as they were, so that its users'
    # devices recognise them.
    def test_the_handle_is_derived_as_given
        climat = Passkey.new(ORIGIN, name: "Climat", handle: "climat/")
        options = climat.registration_for("alice", @keys)
        assert_equal "2RaY7n5qQAN6DYkmTyP7KQo1ZkI_GGOOXmPGpcnEyXM",
                     options.user.id
        assert_equal "Climat", options.rp.name
        refute_equal options.user.id,
                     @passkey.registration_for("alice", @keys).user.id
    end

    # Firefox on Android makes a discoverable passkey only when asked
    # for credProps, under that exact camelCase key.
    def test_registration_asks_for_cred_props
        options = @passkey.registration_for("alice", @keys).as_json
        assert_equal({ credProps: true }, options[:extensions])
    end

    def test_a_registered_passkey_signs_its_owner_in
        enrol("bruno")
        assert_equal "bruno", sign_in
    end

    # Nobody types a name: the credential says whose it is.
    def test_signing_in_names_no_credential
        assert_empty @passkey.authentication.allow_credentials.to_a
    end

    def test_the_record_is_public_and_labelled
        id = enrol(label: "the\tphone ")
        record = @keys.find("alice", id)
        assert_equal "thephone", record.label
        refute_empty record.public_key
        assert_equal "unnamed", Passkey.label(" ")
    end

    def test_a_device_registered_is_excluded_next_time
        id = enrol
        excluded = @passkey.registration_for("alice", @keys)
                           .exclude_credentials
        assert_equal([id], excluded.map { it[:id] })
    end

    def test_an_unregistered_authenticator_is_refused
        enrol
        stranger = WebAuthn::FakeClient.new(ORIGIN)
        stranger.create(challenge: @passkey.authentication.challenge)
        assert_nil sign_in(client: stranger)
    end

    def test_another_challenge_is_refused
        enrol
        assert_nil sign_in(challenge: @passkey.authentication.challenge)
    end

    # A look-alike site relaying the ceremony: the origin is signed.
    def test_another_origin_is_refused
        enrol
        phished = WebAuthn::FakeClient.new("https://app.example.net",
                                           authenticator: @authenticator)
        assert_nil sign_in(client: phished, rp_id: "app.example.org")
    end

    # A user removed takes their passkeys along.
    def test_a_user_removed_is_refused
        enrol("bruno")
        @users.remove("bruno")
        assert_nil sign_in
    end

    def test_a_removed_passkey_no_longer_signs_in
        id = enrol
        assert_empty @keys.remove("alice", id)
        assert_nil sign_in
    end

    def test_a_garbled_answer_is_a_refusal_not_an_error
        assert_nil @passkey.authenticate!({ "id" => "x" }, "y", @keys)
        assert_raises(WebAuthn::Error) do
            @passkey.register!("alice", { "id" => "x" }, "y", @keys,
                               label: "x")
        end
    end

    # Without the gem, the require says what is missing.
    def test_without_webauthn_the_require_says_so
        hide = <<~RUBY
            module Kernel
                alias_method :was, :require
                def require(n) = n == "webauthn" ? raise(LoadError, n) : was(n)
            end
            require "sesam/passkey"
        RUBY
        _, err, = Open3.capture3(RbConfig.ruby, "-Ilib", "-e", hide)
        assert_match(/needs the webauthn gem/, err)
    end

    private

    def enrol(name = "alice", client: @client, label: "phone")
        options = @passkey.registration_for(name, @keys)
        made = client.create(challenge: options.challenge)
        @passkey.register!(name, made, options.challenge, @keys, label:)
    end

    def sign_in(client: @client, challenge: nil, rp_id: nil)
        options = @passkey.authentication
        got = client.get(challenge: challenge || options.challenge, rp_id:)
        @passkey.authenticate!(got, options.challenge, @keys)
    end
end
