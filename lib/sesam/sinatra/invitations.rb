# frozen_string_literal: true

module Sesam
    module Sinatra
        # What an invitation link does (Users#invite): the page reads whose
        # it is, then spends it on a password or a passkey, the token
        # standing for the session there is not yet. It signs no one in:
        # its user then signs in with what they set, their other sessions
        # ended. Open to all (OPEN); lookups that fail are counted by
        # address.
        module Invitations
            CLOSED = "this invitation is not open: used, lapsed or " \
                     "replaced by a newer one"

            # Lookups failed from one address a window.
            BY_LOOKUP = 20

            def self.registered(app)
                app.helpers Helpers
                app.post("/session/invite/check") { invitation_read }
                app.post("/session/invite") { invitation_redeem }
                app.post("/session/invite/challenge") { invited_options }
                app.post("/session/invite/passkey") { invited_passkey }
            end

            # What the routes above call.
            module Helpers
                # Whose invitation this is, without spending it: the page
                # greets them before they choose a password or a passkey.
                def invitation_read
                    invite = invited!
                    password = sesam.with_users { it.password?(invite.user) }
                    answer({ name: invite.user, **sesam_profile(invite.user),
                             expires_at: invite.expires_at, password:,
                             origin: sesam.passkey&.origin,
                             sign_in: sesam.accept.sign_in })
                end

                # Spends the invitation on a password (refused, it stays
                # open); signs no one in.
                def invitation_redeem
                    passwords!
                    password = session_body["password"]
                    refuse(422, "password: needed", "password") unless
                        password.is_a?(String)
                    name = redeemed do |db, user|
                        sesam.users_in(db).password!(user, password)
                    end
                    sesam_notify(name, :password)
                    answer({ name: })
                end

                # The options to register a passkey for the invitation's
                # user; the invitation stays open.
                def invited_options
                    name = invited!.user
                    options = passkey_keys do |keys|
                        passkey!.registration_for(name, keys)
                    end
                    remember(options.challenge)
                    answer(options.as_json)
                end

                # The invitation spent on the passkey registered; one that
                # does not verify leaves it open.
                def invited_passkey
                    name = invited_registration(ceremony,
                                                session_body["label"])
                    sesam_notify(name, :passkey)
                    status(201)
                    answer({ name: })
                rescue *Sinatra.unverified
                    refuse(422, "this passkey could not be registered",
                           "credential")
                end

                private

                # The invitation spent on the passkey the answer registers;
                # its user.
                def invited_registration(credential, label)
                    redeemed do |db, user|
                        passkey!.register!(user, credential, recalled!,
                                           sesam.passkeys_in(db), label:)
                    end
                end

                # The open invitation the token is; a lookup that fails
                # counted by address, and refused alike.
                def invited!
                    lookup_throttled!
                    invite = sesam.with_users { it.invitation(token) }
                    invite || closed!
                end

                # Spends the invitation, the block (given the database and
                # its user) in the same transaction: its user's other
                # sessions end, and the application is told. The user; a
                # refusal of the block's (a password too short), a 422.
                def redeemed
                    lookup_throttled!
                    name = sesam.database do |db|
                        users = sesam.users_in(db)
                        users.redeem(token) do |user|
                            reset!(db, users, user) { yield db, user }
                        end
                    end
                    name || closed!
                rescue Users::Error => e
                    refuse(422, e.message)
                end

                def closed!
                    sesam.throttle.failed!(lookup_key)
                    refuse(404, CLOSED, "token")
                end

                def lookup_throttled!
                    return unless sesam.throttle.blocked?(lookup_key,
                                                          BY_LOOKUP)
                    too_many!
                end

                def lookup_key = "invite:#{sign_in_peer}"
            end
        end
    end
end
