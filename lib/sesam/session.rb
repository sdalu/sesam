# frozen_string_literal: true

require "base64"
require "openssl"

require "rack"

module Sesam
    # A browser's proof of who it is, once signed in: a cookie carrying
    # a name and an expiry signed together, and no secret at all. A
    # stolen session is a session, while the key in a cookie would
    # also be the bearer token for every program. A password, an
    # invitation and a passkey all end here, so everything after reads
    # one thing.
    #
    # Signed with a secret the application keeps, which outlives the
    # process: a secret made per boot would sign everybody out at every
    # restart. Nothing on the server holds a session to revoke: its
    # holder asks whether the name still exists, and whether it was
    # given since the user's sessions were last ended (Held#issued).
    #
    # A passkey's ceremony is two requests, and the challenge the
    # first makes must reach the second, before there is any session
    # to keep it in: it goes back to the browser signed the same way,
    # for minutes, and comes back to be checked. Signed rather than
    # stored: a challenge nobody can forge is as safe held by the
    # client, and no table has to be swept.
    class Session
        # How long a ceremony's challenge lasts, in seconds: the gap
        # between asking the authenticator and its answer.
        CEREMONY = 300

        # A session as the cookie holds it: whose, and when it was
        # given, in milliseconds (a user's sessions end at once, and a
        # session given a moment before must not outlive that).
        Held = Data.define(:name, :issued)

        # The names of the cookie holding a session and of the one
        # holding a ceremony's challenge.
        attr_reader :cookie, :ceremony

        # lifetime: in seconds. cookie, ceremony: the cookies' names,
        # the application's own (a name changed signs everyone out).
        def initialize(secret, lifetime:, cookie: "sesam_session",
                       ceremony: "sesam_ceremony")
            @secret   = secret
            @lifetime = lifetime
            @cookie   = cookie
            @ceremony = ceremony
            freeze
        end

        # The cookie for `name`, scoped to `mount`: the application's
        # (its prefix), not a sub-application's SCRIPT_NAME, or a page
        # mounted beside it would never receive it. Secure, so never
        # sent in clear; HttpOnly, away from scripts; SameSite=Lax, not
        # spent by another site's request.
        def cookie_for(name, mount, now: Time.now)
            held = "#{name}:#{Stamp.ms(now)}"
            attributes(stamp(held, now + @lifetime), mount, @lifetime)
        end

        # The name the request's session says, or nil: forged,
        # tampered with or expired alike, which the holder of a bad
        # cookie need not be told apart.
        def name_from(env, now: Time.now) = held_from(env, now:)&.name

        # The session the request holds (Held), or nil.
        def held_from(env, now: Time.now)
            name, issued = unstamp(cookie_in(env, @cookie), now)
                           &.split(":", 2)
            name && Held.new(name:, issued: Integer(issued))
        rescue ArgumentError, TypeError
            nil
        end

        # The cookie carrying a ceremony's challenge.
        def challenge_cookie(challenge, mount, now: Time.now)
            attributes(stamp(challenge, now + CEREMONY), mount, CEREMONY)
        end

        # The challenge the request's ceremony began with, or nil.
        def challenge_from(env, now: Time.now)
            unstamp(cookie_in(env, @ceremony), now)
        end

        # What replaces a cookie to drop it: every attribute as it was
        # set, the path above all, or the browser keeps the old one
        # and stores this beside it.
        def forget(mount) = attributes("", mount, 0)

        private

        def attributes(value, mount, seconds)
            { value:, max_age: seconds,
              path: mount.to_s.empty? ? "/" : mount.to_s,
              secure: true, httponly: true, same_site: :lax }
        end

        def cookie_in(env, name) = Rack::Request.new(env).cookies[name].to_s

        def stamp(value, expiry)
            payload = Base64.urlsafe_encode64("#{value} #{expiry.to_i}",
                                              padding: false)
            "#{payload}.#{sign(payload)}"
        end

        def unstamp(offered, now)
            payload, mac = offered.split(".", 2)
            return nil unless payload && mac && signed?(payload, mac)
            value, expiry = decode(payload)
            value if value && expiry > now.to_i
        end

        def sign(payload)
            Base64.urlsafe_encode64(
                OpenSSL::HMAC.digest("SHA256", @secret, payload),
                padding: false
            )
        end

        def signed?(payload, mac)
            OpenSSL.secure_compare(sign(payload), mac)
        end

        def decode(payload)
            value, expiry = Base64.urlsafe_decode64(payload).split(" ", 2)
            [value, expiry.to_i]
        rescue ArgumentError
            [nil, 0]
        end
    end
end
