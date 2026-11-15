# frozen_string_literal: true

require "web_support"

# Keys and sessions, and the users they answer with: asserted on the
# name, since a key admitting the right person under the wrong name is
# worse than a refusal.
class CredentialTest < Minitest::Test
    include WebSupport

    def named(env) = Sesam::Credential.new(settings).name_for(env)

    def bearer(text) = { "HTTP_AUTHORIZATION" => text }

    def test_a_key_answers_with_its_user
        assert_equal "alice", named(bearer("Bearer #{ALICE}"))
        assert_equal "bruno", named(bearer("Bearer #{BRUNO}"))
    end

    def test_an_unknown_key_or_a_prefix_is_nobody
        assert_nil named(bearer("Bearer #{ALICE.succ}"))
        assert_nil named(bearer("Bearer #{ALICE[0, 20]}"))
        assert_nil named(bearer("Bearer "))
        assert_nil named({})
    end

    def test_the_bearer_scheme_is_required
        assert_nil named(bearer(ALICE))
        assert_nil named(bearer("Basic #{ALICE}"))
    end

    # A link must not act.
    def test_a_query_string_key_does_not_admit
        assert_nil named("QUERY_STRING" => "key=#{ALICE}")
    end

    def test_a_session_counts_while_its_user_has_not_ended_it
        assert_equal "bruno", named(cookie_env("bruno"))
        users.end_sessions!("bruno", now: Time.now + 1)
        assert_nil named(cookie_env("bruno"))
        assert_nil named(cookie_env("carol"))
    end
end
