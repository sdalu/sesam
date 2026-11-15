# frozen_string_literal: true

require "web_support"

# A link asked for from the sign-in screen (recovery): by a login name
# or an email address, the same answer whether or not it names
# anyone; an invitation made and handed to the application to mail
# only for a user it can reach, and counted by address and by name.
class RecoveryTest < Minitest::Test
    include WebSupport

    ASKED = { "data" => { "asked" => true } }.freeze

    def setup
        super
        @given = { recovery: true }
        @profiles["alice"] = { email: "alice@example.org" }
    end

    def test_off_unless_said
        @given = {}
        assert_equal 404, ask("alice")
    end

    def test_by_name_a_link_is_handed_over
        assert_equal 202, ask("alice")
        assert_equal ASKED, reply
        name, token = invited.first
        assert_equal "alice", name
        assert_equal "alice", users.invitation(token).user
    end

    def test_by_email_the_same
        ask("alice@example.org")
        assert_equal ["alice"], invited.map(&:first)
    end

    # Nobody, or somebody with no address: the same answer, nothing
    # left open (an open invitation of theirs stays theirs).
    def test_nobody_and_the_unreachable_get_the_same_answer
        open = users.invite("bruno")
        [ask("carol"), ask("bruno")].each { assert_equal 202, it }
        assert_equal ASKED, reply
        refute_nil users.invitation(open)
        assert_equal 1, @db[:invites].count
    end

    def test_a_link_lasts_an_hour
        ask("alice")
        token = invited.first.last
        lapse = users.invitation(token).expires_at - Time.now
        assert_in_delta 3600, lapse, 5
    end

    # A name is asked for three times a window at most, silently: the
    # answer the same, no more mail.
    def test_a_name_is_mailed_three_times_a_window
        5.times { assert_equal 202, ask("alice", peer: "198.51.100.#{it}") }
        assert_equal 3, invited.size
    end

    # An address asks twenty times a window, then waits.
    def test_an_address_asks_twenty_times_a_window
        20.times { ask("carol#{it}") }
        assert_equal 429, ask("alice")
    end

    # The sign-in screen learns it from a 401: `recover` among the ways.
    def test_a_refusal_says_a_link_may_be_asked_for
        call(:get, "/secret")
        assert_equal "password passkey recover",
                     last_response.headers["X-App-Sign-In"]
    end

    # A link handed over is told, in the invitation's transaction; one
    # for nobody, not.
    def test_a_link_handed_over_is_told
        ask("carol")
        ask("alice")
        asked = @told.select { it.first == :asked }
        assert_equal [[:asked, "alice", true]], asked
    end

    # The answer does not wait for the link: a mail takes its time only
    # for a user who exists.
    def test_the_answer_does_not_wait_for_the_link
        mailed = Thread::Queue.new
        app.define_method(:sesam_reached?) { |*| mailed.pop(timeout: 5) }
        assert_equal 202, call(:post, "/session/recover", { who: "alice" })
        handover = last_request.env[Sesam::Sinatra::Recovery::HANDOVER]
        assert_instance_of Thread, handover
        assert_predicate handover, :alive?
        mailed << true
        handover.join
        assert_equal 1, @db[:invites].count
    end

    # A hand-over that fails is said on the server's output, no link
    # kept; the answer was given already.
    def test_a_hand_over_that_fails_is_said
        app.define_method(:sesam_reached?) { |*| raise IOError, "no mail" }
        assert_output(nil, /no link for alice: IOError: no mail/) do
            assert_equal 202, ask("alice")
        end
        assert_equal 0, @db[:invites].count
    end

    private

    # Asked, and the link handed over, if one is: what the tests read
    # is written then.
    def ask(who, peer: WAN)
        status = call(:post, "/session/recover", { who: }, peer:)
        last_request.env[Sesam::Sinatra::Recovery::HANDOVER]&.join
        status
    end

    def invited = @told.select { it.first == :invited }.map { it.drop(1) }
end
