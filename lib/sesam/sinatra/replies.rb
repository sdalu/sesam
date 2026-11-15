# frozen_string_literal: true

require "json"

module Sesam
    module Sinatra
        # A refusal decided by a route, raised rather than halted: an
        # exception rolls back the transaction it crosses (an invitation
        # stays open), where Sinatra's halt, a throw, would commit it.
        # http_status keeps Sinatra from raising it on in tests.
        class Refused < StandardError
            attr_reader :status, :field

            def initialize(status, message, field = nil)
                super(message)
                @status = status
                @field  = field&.to_s
            end

            def http_status = @status
        end

        # How the routes answer where the application says nothing: JSON,
        # { data } on success, { error, field } on a refusal, both sent
        # as application/json rather than Sinatra's text/html default.
        module Replies
            def answer(data)
                content_type :json
                JSON.generate({ data: })
            end

            def refuse(status, message, field = nil)
                raise Refused.new(status, message, field)
            end

            # What a Refused answers (Sesam::Sinatra.registered).
            def refusal(failed)
                content_type :json
                status failed.status
                JSON.generate({ error: failed.message, field: failed.field })
            end

            # The request's JSON object, {} for none; a body is JSON, said
            # so (415 else): a page elsewhere can make a browser post
            # text/plain without a preflight, application/json only after
            # one no foreign origin passes.
            def parsed_body
                text = request.body.read.to_s
                return {} if text.strip.empty?
                unless request.media_type == "application/json"
                    refuse(415, "body: Content-Type application/json", "body")
                end
                body = JSON.parse(text)
                return body if body.is_a?(Hash)
                refuse(422, "body: a JSON object", "body")
            rescue JSON::ParserError
                refuse(422, "body: not JSON", "body")
            end
        end

        # What the application is told, where it says nothing: nothing.
        module Hooks
            # A user's way in changed, in `db`'s transaction: a password
            # set, a passkey registered or removed, an invitation spent.
            def sesam_changed(_name, _db) = nil

            # After it: kind, :password or :passkey set for `name`.
            def sesam_notify(_name, _kind) = nil

            # What GET /session and an invitation's check say of `name`
            # besides (nil for no user).
            def sesam_profile(_name) = {}

            # The user an email address (or another name for them) is,
            # for a link asked for (recovery); nil for none.
            def sesam_named(_text) = nil

            # A link asked for: hand `token`'s invitation to `name`;
            # whether it reached them (false: no invitation is kept).
            # Called after the answer, off the request's thread (Recovery),
            # as sesam_asked is: what they need of the request is read
            # from it, never from a thread-local.
            def sesam_reached?(_name, _token) = false

            # A link asked for and handed to `name`, in the invitation's
            # transaction in `db` (an audit row, the caller's).
            def sesam_asked(_name, _db) = nil
        end
    end
end
