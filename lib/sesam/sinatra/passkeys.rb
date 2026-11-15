# frozen_string_literal: true

module Sesam
    module Sinatra
        # Passkeys (Sesam::Passkey) as requests: signing in with one, and
        # the ones a user keeps. Each ceremony is two calls: this side says
        # what to sign, the authenticator signs, this side checks; the
        # challenge between them rides in a signed cookie
        # (Session#challenge_cookie). Signing in is open (OPEN);
        # registering with an invitation is Invitations'. The rest is a
        # user's, signed in.
        module Passkeys
            def self.registered(app)
                app.helpers Helpers
                app.post("/session/challenge") { sign_in_options }
                app.post("/session") { sign_in }
                app.get("/passkeys") { passkeys_read }
                app.post("/passkeys/challenge") { registration_options }
                app.post("/passkeys") { passkey_add }
                app.delete("/passkeys/:id") { passkey_remove }
            end

            # What the routes above call.
            module Helpers
                def sign_in_options
                    options = passkey!.authentication
                    remember(options.challenge)
                    answer(options.as_json)
                end

                # The assertion: a user back means the signature verified,
                # for a credential registered here, over the challenge set.
                # Which of those failed is not said: it would tell a caller
                # what to change.
                def sign_in
                    credential = ceremony
                    name = passkey_keys do |keys|
                        passkey!.authenticate!(credential, recalled!, keys)
                    end
                    refuse(403, "passkey refused") unless name
                    signed_in!(name)
                    answer({ name: })
                end

                def passkeys_read
                    name = named!
                    answer(passkey_keys { it.of(name) }.map do |key|
                        { id: key.id, label: key.label,
                          created_at: key.created_at }
                    end)
                end

                def registration_options
                    name = named!
                    options = passkey_keys do |keys|
                        passkey!.registration_for(name, keys)
                    end
                    remember(options.challenge)
                    answer(options.as_json)
                end

                def passkey_add
                    name = named!
                    id = registered(name, ceremony, session_body["label"])
                    status(201)
                    answer({ id: })
                end

                # The last one may go too: an invitation still brings its
                # user back.
                def passkey_remove
                    name = named!
                    id = params["id"].to_s
                    kept = passkey_written(name) do |keys|
                        refuse(404, "no passkey #{id}", "id") unless
                            keys.find(name, id)
                        keys.remove(name, id)
                    end
                    answer({ remaining: kept.size })
                end

                private

                # 404 where passkeys are not offered: to a caller, a
                # feature not offered is a route that is not there.
                def passkey!
                    sesam.passkey ||
                        refuse(404, "passkeys are not configured here")
                end

                # The id the authenticator's answer registers, told the
                # application; 422 for an answer that does not verify.
                def registered(name, credential, label)
                    passkey_written(name) do |keys|
                        passkey!.register!(name, credential, recalled!, keys,
                                           label:)
                    end
                rescue *Sinatra.unverified
                    refuse(422, "this passkey could not be registered",
                           "credential")
                end

                def passkey_keys
                    sesam.database { yield sesam.passkeys_in(it) }
                end

                # The block's change to `name`'s passkeys, told the
                # application in its transaction.
                def passkey_written(name)
                    sesam.database do |db|
                        db.transaction do
                            result = yield sesam.passkeys_in(db)
                            sesam_changed(name, db)
                            result
                        end
                    end
                end

                # The authenticator's answer, from the body.
                def ceremony
                    credential = session_body["credential"]
                    return credential if credential.is_a?(Hash)
                    refuse(422, "credential: the authenticator's answer, " \
                                "an object", "credential")
                end

                def remember(challenge)
                    session = sesam.session or
                        refuse(404, "signing in is not configured here")
                    response.set_cookie(
                        session.ceremony,
                        session.challenge_cookie(challenge, sesam.mount)
                    )
                end

                # The challenge, spent: dropped whatever the answer.
                def recalled!
                    session = sesam.session
                    challenge = session.challenge_from(request.env)
                    response.set_cookie(session.ceremony,
                                        session.forget(sesam.mount))
                    challenge || refuse(422, "the ceremony expired: start " \
                                             "again")
                end
            end
        end
    end
end
