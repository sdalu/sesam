# frozen_string_literal: true

require "web_support"

# What a reset by invitation does to the passkeys and the sessions a
# user had (reset_passkeys): keep (the passkeys kept, the other
# sessions ended), drop (both gone), drop_keep_sessions (the passkeys
# gone, the sessions kept). The passkey the invitation registers is
# kept in every case.
class ResetTest < Minitest::Test
    include WebSupport

    def setup
        super
        @client = WebAuthn::FakeClient.new(ORIGIN)
        Sesam::Passkeys.new(@db).add("alice", id: "old", public_key: "pk",
                                              sign_count: 0, label: "lost")
    end

    def test_keep_ends_the_sessions_and_keeps_the_passkeys
        assert_equal [false, ["old"]], reset_by_password
    end

    def test_drop_ends_both
        @given = { reset_passkeys: "drop" }
        assert_equal [false, []], reset_by_password
    end

    def test_drop_keep_sessions_drops_the_passkeys_alone
        @given = { reset_passkeys: "drop_keep_sessions" }
        assert_equal [true, []], reset_by_password
    end

    def test_the_passkey_the_invitation_registers_is_kept
        @given = { reset_passkeys: "drop" }
        token = users.invite("alice")
        call(:post, "/session/invite/challenge", { token: })
        made = @client.create(challenge: reply.dig("data", "challenge"))
        assert_equal 201, call(:post, "/session/invite/passkey",
                               { token:, credential: made })
        ids = Sesam::Passkeys.new(@db).of("alice").map(&:id)
        assert_equal 1, ids.size
        refute_includes ids, "old"
    end

    private

    # alice signed in, then reset by an invitation spent on a password,
    # a second on: whether her first session still counts, and the
    # passkeys she keeps.
    def reset_by_password
        signed_in_as_alice
        issued = held_issued
        travel(1) do
            token = users.invite("alice")
            call(:post, "/session/invite", { token:, password: "z" * 12 })
        end
        [users.session_valid?("alice", issued),
         Sesam::Passkeys.new(@db).of("alice").map(&:id)]
    end

    # When the browser's session was given.
    def held_issued
        signed = rack_mock_session.cookie_jar["sesam_session"]
        session.held_from({ "HTTP_COOKIE" => "sesam_session=#{signed}" })
               .issued
    end

    def travel(seconds, &)
        later = Time.now + seconds
        Time.stub(:now, later, &)
    end
end
