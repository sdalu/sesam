# frozen_string_literal: true

module Sesam
    module Sinatra
        # How a browser becomes a user: who it is now (GET /session), a
        # password, a passkey (Passkeys), and signing out; an invitation
        # (Invitations) sets a password or registers a passkey and signs
        # no one in.
        #
        # Failures are counted (Throttled); what was wrong is never said.
        # A password set or changed ends the user's other sessions
        # (Users#end_sessions!).
        module Sessions
            def self.registered(app)
                app.helpers Helpers, Throttled
                app.get("/session") { whoami }
                app.post("/session/password") { password_sign_in }
                app.put("/session/password") { password_change }
                app.delete("/session") { sign_out }
            end

            # What the routes above call.
            module Helpers
                # Who the gate admitted, whether they have a password, the
                # origin passkeys are bound to (nil: none here), which the
                # page compares with its own, and the browser's ways in.
                def whoami
                    answer(profiled(@caller.user,
                                    { name: who, via: @caller.verdict.to_s,
                                      password: password_set?,
                                      origin: sesam.passkey&.origin,
                                      sign_in: sesam.accept.sign_in }))
                end

                def password_sign_in
                    passwords!
                    name = session_body["name"].to_s
                    password_checked!(name)
                    signed_in!(name)
                    answer({ name: })
                end

                # Its own password, the current one given when there is
                # one: a session left open somewhere must not be enough to
                # take the account. Its other sessions end; this browser's
                # is given again.
                def password_change
                    passwords!
                    name = named!
                    changed_password(name, new_password)
                    signed_in!(name)
                    sesam_notify(name, :password)
                    answer({ name: })
                end

                # The session dropped (HttpOnly: the page cannot). A LAN
                # browser stays admitted, the network being its credential.
                def sign_out
                    @caller = sesam.access.caller_for(request.env)
                    @caller = nil if @caller.refused?
                    session = sesam.session
                    if session
                        response.set_cookie(session.cookie,
                                            session.forget(sesam.mount))
                    end
                    answer({ signed_out: true })
                end

                private

                # `name`'s password, as the body gives it, or 403, counted;
                # their failures forgotten once it matches.
                def password_checked!(name)
                    sign_in_throttled!(name)
                    given = session_body["password"]
                    unless sesam.with_users { it.password_match?(name, given) }
                        sign_in_failed!(name, "name or password refused")
                    end
                    sesam.throttle.clear!(try_key(name))
                end

                # 404 where passwords are not accepted.
                def passwords!
                    return if sesam.accept.include?("password")
                    refuse(404, "passwords are not offered here")
                end

                def token = session_body["token"].to_s

                # The password the body gives, text; 422 else.
                def new_password
                    password = session_body["password"]
                    return password if password.is_a?(String)
                    refuse(422, "password: needed", "password")
                end

                # What sesam says (`ours`), the application's profile of
                # `name` beside it. A profile naming one of sesam's keys
                # (a display name as `name`) would speak for sesam: an
                # error, never an answer.
                def profiled(name, ours)
                    profile = sesam_profile(name).to_h
                    clash = profile.keys.map(&:to_sym) & ours.keys
                    return ours.merge(profile) if clash.empty?
                    raise Sesam::Error, "sesam_profile: #{clash.join(", ")} " \
                                        "is sesam's own key"
                end

                # The body, read once: a stream reads once.
                def session_body = @session_body ||= parsed_body

                def password_set?
                    return false unless @caller.verdict == :credential
                    sesam.with_users { it.password?(who) }
                end

                # The block's change to `name`'s way in, their sessions
                # ended unless `sessions` is false, told the application, in
                # one transaction.
                def reset!(store, users, name, sessions: true)
                    store.transaction do
                        yield
                        users.end_sessions!(name) if sessions
                        sesam_changed(name, store)
                    end
                end

                # Set after the current one is checked; one refused is a
                # 422 saying why.
                def changed_password(name, password)
                    sesam.store do |store|
                        users = sesam.users_in(store)
                        current!(users, name)
                        reset!(store, users, name) do
                            users.password!(name, password)
                        end
                    end
                rescue Users::Error => e
                    refuse(422, e.message)
                end

                def current!(users, name)
                    return unless users.password?(name)
                    sign_in_throttled!(name)
                    return if users.password_match?(name,
                                                    session_body["current"])
                    sign_in_failed!(name, "the current password is refused")
                end

                # A user, not the LAN: a password and a passkey belong to
                # one.
                def named!
                    return who if @caller.verdict == :credential
                    refuse(403, "this needs a user signed in: open your " \
                                "invitation link")
                end
            end
        end
    end
end
