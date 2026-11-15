# frozen_string_literal: true

require "web_support"

# The ceremonies as a browser goes through them: signed in by password,
# a passkey registered, signed out, signed in again by the passkey
# alone; with an invitation; and the doors that stay shut.
class PasskeyRoutesTest < Minitest::Test
    include WebSupport

    def setup
        super
        @client = WebAuthn::FakeClient.new(ORIGIN)
    end

    def test_a_passkey_signs_in_after_signing_out
        signed_in_as_alice
        assert_equal 201, register
        assert_equal [:changed, "alice", true], @told.last
        call(:delete, "/session")
        assert_equal 401, call(:get, "/secret")
        assert_equal 200, sign_in
        assert_equal "alice", reply.dig("data", "name")
        assert_equal 200, call(:get, "/secret")
    end

    def test_the_list_names_the_device
        signed_in_as_alice
        register("the phone")
        id = listed_as("the phone")
        assert_equal 200, call(:delete, "/passkeys/#{id}")
        assert_equal 0, reply.dig("data", "remaining")
        assert_equal 404, call(:delete, "/passkeys/#{id}")
    end

    def test_registering_needs_a_name
        assert_equal 401, call(:post, "/passkeys/challenge")
        assert_equal 403, call(:post, "/passkeys/challenge", peer: LAN)
    end

    def test_an_unknown_passkey_is_refused
        signed_in_as_alice
        register
        call(:delete, "/session")
        stranger = WebAuthn::FakeClient.new(ORIGIN)
        stranger.create(challenge: "AAAA")
        assert_equal 403, sign_in(stranger)
    end

    # The challenge is spent with the answer: replaying fails.
    def test_a_ceremony_without_its_challenge_is_refused
        signed_in_as_alice
        register
        call(:delete, "/session")
        call(:post, "/session/challenge")
        got = @client.get(challenge: reply.dig("data", "challenge"))
        assert_equal 200, call(:post, "/session", { credential: got })
        assert_equal 422, call(:post, "/session", { credential: got })
    end

    def test_an_answer_not_verifying_is_refused
        signed_in_as_alice
        call(:post, "/passkeys/challenge")
        assert_equal 422, call(:post, "/passkeys",
                               { credential: { "id" => "x" } })
    end

    def test_passkeys_not_accepted_no_routes
        @given = { accept: %w[key password] }
        assert_equal 404, call(:post, "/session/challenge")
        call(:get, "/session", peer: LAN)
        assert_equal [nil, %w[password]],
                     reply["data"].values_at("origin", "sign_in")
    end

    # An invitation registers a passkey, the token standing for the
    # session: no one is signed in, the passkey then signs alice in.
    def test_an_invitation_registers_a_passkey
        token = users.invite("alice")
        assert_equal 200, call(:post, "/session/invite/challenge", { token: })
        made = @client.create(challenge: reply.dig("data", "challenge"))
        assert_equal 201, call(:post, "/session/invite/passkey",
                               { token:, credential: made, label: "phone" })
        assert_equal 401, call(:get, "/secret")
        assert_equal 200, sign_in
        assert_equal 404, call(:post, "/session/invite/challenge", { token: })
    end

    def test_a_passkey_set_by_invitation_is_told
        token = users.invite("alice")
        call(:post, "/session/invite/challenge", { token: })
        made = @client.create(challenge: reply.dig("data", "challenge"))
        call(:post, "/session/invite/passkey", { token:, credential: made })
        assert_equal [[:changed, "alice", true],
                      [:notify, "alice", :passkey]], @told
    end

    # An answer that does not verify leaves the invitation open.
    def test_a_refused_passkey_keeps_the_invitation
        token = users.invite("alice")
        call(:post, "/session/invite/challenge", { token: })
        assert_equal 422, call(:post, "/session/invite/passkey",
                               { token:, credential: { "id" => "x" } })
        assert_equal 200, call(:post, "/session/invite/check", { token: })
    end

    private

    # The one passkey GET /passkeys lists, under its label: its id.
    def listed_as(label)
        call(:get, "/passkeys")
        listed = reply["data"]
        assert_equal([label], listed.map { it["label"] })
        listed.first["id"]
    end

    def register(label = "phone")
        call(:post, "/passkeys/challenge")
        made = @client.create(challenge: reply.dig("data", "challenge"))
        call(:post, "/passkeys", { credential: made, label: })
    end

    def sign_in(client = @client)
        call(:post, "/session/challenge")
        got = client.get(challenge: reply.dig("data", "challenge"))
        call(:post, "/session", { credential: got })
    end
end
