# frozen_string_literal: true

require "json"

module Sesam
    module Sinatra
        # How the routes answer where the application says nothing: JSON,
        # { data } on success, { error, field } on a refusal.
        module Replies
            def answer(data) = JSON.generate({ data: })

            def refuse(status, message, field = nil)
                halt status, JSON.generate({ error: message,
                                             field: field&.to_s })
            end

            # The request's JSON object, {} for none.
            def parsed_body
                text = request.body.read.to_s
                body = text.strip.empty? ? {} : JSON.parse(text)
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
        end
    end
end
