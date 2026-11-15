# frozen_string_literal: true

module Sesam
    module Sinatra
        # The application's door, run before every route but those open to
        # all (#sesam_open?): who is calling (Access), refused with a 401
        # and the ways past it; and the session a browser is given once it
        # has proved who it is (a password, a passkey), the one thing it
        # cannot keep for itself.
        module Gate
            # Admits the caller, remembered for the route (#who), or
            # refuses it: WWW-Authenticate, and the browser's ways in for
            # a sign-in screen to offer (empty for none).
            def admit!
                @caller = sesam.access.caller_for(request.env)
                return unless @caller.refused?
                headers("WWW-Authenticate" => sesam.realm,
                        sesam.sign_in_header => sesam.accept.sign_in.join(" "))
                refuse(401, "sign in, or send a key from this network: " \
                            "Authorization: Bearer KEY")
            end

            def sesam_open?
                OPEN.include?([request.request_method, request.path_info])
            end

            # Who is calling: a user's name, lan:ADDR, or nil before the
            # gate.
            def who = @caller&.name

            # The browser signed in as `name`: a session (the name, signed;
            # no secret in it) scoped to the mount; 404 where there is no
            # session to give.
            def signed_in!(name)
                session = sesam.session or
                    refuse(404, "signing in is not configured here")
                @caller = Access::Caller.new(verdict: :credential, name:,
                                             user: name)
                response.set_cookie(session.cookie,
                                    session.cookie_for(name, sesam.mount))
            end

            private

            def sesam = settings.sesam
        end
    end
end
