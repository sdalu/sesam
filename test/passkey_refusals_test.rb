# frozen_string_literal: true

require "base64"

require "web_support"

# The passkey ceremonies' refusals, each leaving everything as it was:
# an invitation stays open whatever refused it, a challenge is spent
# once even when its cookie is sent again, a credential id is one
# user's, and an answer that is no JSON is a refusal, not an error.
class PasskeyRefusalsTest < Minitest::Test
    include WebSupport

    def setup
        super
        @client = WebAuthn::FakeClient.new(ORIGIN)
    end

    # A ceremony that lapsed: refused, the invitation open, nothing told.
    def test_a_lapsed_invited_passkey_keeps_the_invitation
        token = users.invite("alice")
        call(:post, "/session/invite/challenge", { token: })
        made = @client.create(challenge: reply.dig("data", "challenge"))
        clear_cookies
        assert_equal 422, call(:post, "/session/invite/passkey",
                               { token:, credential: made })
        refute_nil users.invitation(token)
        assert_empty @told
    end

    def test_passkeys_not_offered_keep_the_invitation
        @given = { accept: %w[key password] }
        token = users.invite("alice")
        assert_equal 404, call(:post, "/session/invite/passkey",
                               { token:, credential: { "id" => "x" } })
        refute_nil users.invitation(token)
    end

    # The same answer with the same cookie, sent again, is refused (a
    # synced passkey's counter stays at 0 and cannot tell).
    def test_a_replay_with_its_cookie_is_refused
        ceremony, got = signed_out_with_an_answer
        assert_equal 200, call(:post, "/session", { credential: got },
                               "HTTP_COOKIE" => ceremony)
        clear_cookies
        assert_equal 422, call(:post, "/session", { credential: got },
                               "HTTP_COOKIE" => ceremony)
    end

    # bruno's authenticator offers alice's credential id: refused, and
    # alice keeps hers.
    def test_another_user_s_credential_id_is_refused
        signed_in_as_alice
        register(@client)
        alice = @db[:passkeys].get(:id)
        clear_cookies
        users.password!("bruno", PASSWORD)
        call(:post, "/session/password", { name: "bruno", password: PASSWORD })
        assert_equal 422, register(impostor(alice))
        assert_equal [[alice, "alice"]], @db[:passkeys].select_map(%i[id user])
    end

    def test_client_data_that_is_no_json_is_refused
        ceremony, got = signed_out_with_an_answer
        got["response"]["clientDataJSON"] = "eHh4"
        assert_equal 403, call(:post, "/session", { credential: got },
                               "HTTP_COOKIE" => ceremony)
        signed_in_as_alice
        call(:post, "/passkeys/challenge")
        made = @client.create(challenge: reply.dig("data", "challenge"))
        made["response"]["clientDataJSON"] = "eHh4"
        assert_equal 422, call(:post, "/passkeys", { credential: made })
    end

    private

    # alice with a passkey, signed out; a sign-in ceremony begun: its
    # cookie, and the authenticator's answer (counter at 0).
    def signed_out_with_an_answer
        signed_in_as_alice
        register(@client)
        call(:delete, "/session")
        clear_cookies
        call(:post, "/session/challenge")
        ceremony = last_response.headers["set-cookie"][/sesam_ceremony=[^;]+/]
        [ceremony, @client.get(challenge: reply.dig("data", "challenge"),
                               sign_count: 0)]
    end

    def register(client)
        call(:post, "/passkeys/challenge")
        made = client.create(challenge: reply.dig("data", "challenge"))
        call(:post, "/passkeys", { credential: made, label: "phone" })
    end

    # A client whose authenticator makes credentials under `id`.
    def impostor(id)
        raw = Base64.urlsafe_decode64(id)
        authenticator = WebAuthn::FakeAuthenticator.new
        authenticator.define_singleton_method(:new_credential) do |_alg|
            [raw, OpenSSL::PKey::EC.generate("prime256v1"), 0]
        end
        WebAuthn::FakeClient.new(ORIGIN, authenticator:)
    end
end
