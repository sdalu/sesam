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
                def invitation_read # rubocop:disable Metrics/AbcSize
                    invite = invited!
                    password = sesam.with_users { it.password?(invite.user) }
                    answer(profiled(invite.user,
                                    { name: invite.user,
                                      expires_at:
                                          invite.expires_at.xmlschema(3),
                                      password:,
                                      origin: sesam.passkey&.origin,
                                      sign_in: sesam.accept.sign_in }))
                end

                # Spends the invitation on a password (refused, it stays
                # open); signs no one in.
                def invitation_redeem
                    passwords!
                    password = new_password
                    name = redeemed do |store, user|
                        sesam.users_in(store).password!(user, password)
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
                    redeemed do |store, user|
                        passkey!.register!(user, credential, recalled!,
                                           sesam.passkeys_in(store), label:)
                    end
                end

                # The open invitation the token is; a lookup that fails
                # counted by address, and refused alike.
                def invited!
                    lookup_throttled!
                    invite = sesam.with_users { it.invitation(token) }
                    invite || closed!
                end

                # Spends the invitation, the block (given the store and
                # its user) in the same transaction, after the passkeys
                # they had are dropped where reset_passkeys says: their
                # other sessions end (but drop_keep_sessions), and the
                # application is told. The user; a refusal of the block's
                # (a password too short), a 422.
                def redeemed
                    lookup_throttled!
                    name = sesam.store do |store|
                        users = sesam.users_in(store)
                        users.redeem(token) do |user|
                            spend(store, users, user) { yield store, user }
                        end
                    end
                    name || closed!
                rescue Users::Error => e
                    refuse(422, e.message)
                end

                def spend(store, users, user, &)
                    mode = sesam.reset_passkeys
                    sesam.passkeys_in(store).clear(user) unless mode == "keep"
                    reset!(store, users, user,
                           sessions: mode != "drop_keep_sessions", &)
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
