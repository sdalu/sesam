# frozen_string_literal: true

module Sesam
    module Sinatra
        # A link asked for from the sign-in screen, where the settings
        # allow it (Settings#recovery): by a login name or anything the
        # application knows a user by (sesam_named: an email address),
        # answered the same whether or not it names anyone, so that
        # asking tells nobody who exists. For a user the application
        # can reach (sesam_reached?, which mails the link), an invitation
        # lasting recovery_for; for anyone else, nothing, and their open
        # invitation stays theirs. Open to all (OPEN); counted by
        # address (429 past BY_PEER) and, silently, by name (BY_NAME),
        # so that nobody is mailed without end.
        module Recovery
            BY_PEER = 20
            BY_NAME = 3

            def self.registered(app)
                app.helpers Helpers
                app.post("/session/recover") { recover }
            end

            # What the route above calls.
            module Helpers
                def recover
                    recovery!
                    asked!
                    name = recovered(session_body["who"].to_s.strip)
                    invited(name) if name
                    status(202)
                    answer({ asked: true })
                end

                private

                # Each ask counted by address: past BY_PEER, 429.
                def asked!
                    peer = "recover:#{sign_in_peer}"
                    too_many! if sesam.throttle.blocked?(peer, BY_PEER)
                    sesam.throttle.failed!(peer)
                end

                # 404 where links are not asked for here.
                def recovery!
                    return if sesam.recovery
                    refuse(404, "links are not asked for here")
                end

                # The user `who` names: a login, else whom the
                # application knows by it; nil for none, or for one asked
                # for too often.
                def recovered(who)
                    return nil if who.empty? || who.length > 254
                    name = sesam.with_users { it.exists?(who) } ? who : nil
                    name ||= sesam_named(who)
                    key = "recover-name:#{name}"
                    return nil if name.nil? ||
                                  sesam.throttle.blocked?(key, BY_NAME)
                    sesam.throttle.failed!(key)
                    name
                end

                # An invitation for `name`, kept only if the application
                # handed it over, and then told it (sesam_asked) in the
                # same transaction.
                def invited(name)
                    sesam.database do |db|
                        seconds = sesam.recovery_for
                        sesam.users_in(db).invite(name, seconds:) do |token|
                            raise Sequel::Rollback unless
                                sesam_reached?(name, token)
                            sesam_asked(name, db)
                        end
                    end
                end
            end
        end
    end
end
