# frozen_string_literal: true

require "base64"
require "json"
require "openssl"
require "uri"

begin
    require "webauthn"
rescue LoadError
    raise LoadError, "sesam/passkey needs the webauthn gem: add it to " \
                     "the application's Gemfile"
end

require "sesam"

module Sesam
    # The WebAuthn half of who is calling, beside a password and an
    # API key. The caller holds a private key that never leaves the
    # authenticator, the database keeps the public half (Passkeys), and
    # the proof is a signature over a challenge just made up, bound to
    # the origin: nothing here, in a backup or in a log, signs.
    #
    # A passkey is per device and no program can present one, so a
    # password or an invitation (Users#invite) stays the way back in,
    # and a key what a script sends.
    #
    # Registering is something a user does to themselves, signed in
    # (by an invitation the first time): a ceremony that could create a
    # user would be an open door with more steps. Signing in asks for
    # no name: the authenticator offers what it holds for the origin,
    # and the credential's id says whose it is. A user removed takes
    # their passkeys along.
    class Passkey
        # An origin no browser would sign at.
        class Error < Sesam::Error; end

        # An origin: https and a host, else http on localhost, which
        # browsers count as secure; no path.
        # What an answer the gem cannot read raises.
        UNREADABLE = [ArgumentError, TypeError, NoMethodError, KeyError,
                      JSON::ParserError].freeze

        ORIGIN = %r{\A(?:https://[^/\s:]+|http://localhost)(?::\d+)?\z}

        # `given` as an origin, a trailing slash taken off; Error for
        # one no browser would sign at. The application's configured
        # one, never read from a request: WebAuthn binds a credential to
        # the origin the browser sees, and behind a proxy the request
        # says what the proxy wrote.
        def self.origin!(given)
            text = given.to_s.strip.chomp("/")
            return text if ORIGIN.match?(text)
            raise Error, "origin: https://HOST[:PORT], no path, " \
                         "not #{given.inspect}"
        end

        # The one passkeys are bound to.
        attr_reader :origin

        # name: what the browser shows when it asks for a finger.
        # handle: what each user's handle is derived from, before their
        # name; the application's own, since a handle changed makes
        # every device register a second credential for the same user.
        def initialize(origin, name: "Sesam", handle: "sesam/")
            @origin = Passkey.origin!(origin)
            @handle = handle
            @party = WebAuthn::RelyingParty.new(
                allowed_origins: [@origin], id: URI(@origin).host, name:
            )
        end

        # The options for navigator.credentials.create; keys: the
        # store's Passkeys.
        def registration_for(name, keys)
            @party.options_for_registration(
                user: { id: handle_for(name), name:, display_name: name },
                # Stored by the authenticator, so it can be offered
                # later without being told whom we look for.
                authenticator_selection: { resident_key: "required",
                                           user_verification:
                                               "preferred" },
                # Asked for, or Firefox on Android never passes the
                # resident key on and the passkey cannot sign in.
                extensions: { credProps: true },
                # A device registered already says so rather than
                # registering twice.
                exclude: keys.of(name).map(&:id)
            )
        end

        # The id registered; WebAuthn::Error when it does not verify,
        # an answer the gem cannot even read included.
        def register!(name, credential, challenge, keys, label:)
            verified = @party.verify_registration(
                credential, challenge, user_verification: false
            )
            keys.add(name, id: verified.id,
                           public_key: verified.public_key,
                           sign_count: verified.sign_count,
                           label: Passkey.label(label))
            verified.id
        rescue *UNREADABLE, Passkeys::Error => e
            raise WebAuthn::Error, "unreadable answer (#{e.class})"
        end

        # The options for navigator.credentials.get. No allow-list:
        # naming the credentials we accept would tell anybody which
        # users exist.
        def authentication
            @party.options_for_authentication(
                user_verification: "preferred"
            )
        end

        # The user this assertion proves, or nil: a signature that does
        # not verify, a credential nobody here registered, a challenge
        # not ours, are all one ordinary refusal.
        def authenticate!(credential, challenge, keys)
            name, verified = verify(credential, challenge, keys)
            keys.seen(name, verified.id, verified.sign_count)
            name
        rescue WebAuthn::Error, *UNREADABLE
            nil
        end

        # A label is shown to its owner alone: short, and text.
        def self.label(given)
            text = given.to_s.gsub(/[[:cntrl:]]/, "").strip
            text.empty? ? "unnamed" : text[0, 60]
        end

        private

        # The user and the verified credential; WebAuthn::Error when
        # the signature, the challenge, the origin or the credential
        # is not ours.
        def verify(credential, challenge, keys)
            name = nil
            verified, = @party.verify_authentication(
                credential, challenge, user_verification: false
            ) do |offered|
                name, record = registered!(offered.id, keys)
                record
            end
            [name, verified]
        end

        # Stable, opaque, derived rather than stored: the same on every
        # device and after every restart. A digest, not the name,
        # since the authenticator keeps it and may show it; base64url,
        # because the gem writes it into JSON as given.
        def handle_for(name)
            Base64.urlsafe_encode64(
                OpenSSL::Digest.digest("SHA256", "#{@handle}#{name}"),
                padding: false
            )
        end

        # Whose credential `id` is, and the record whose public key
        # checks the signature: the signature proves an authenticator
        # answered, not that this deployment ever agreed to trust it.
        def registered!(id, keys)
            name = keys.owner_of(id)
            found = name && keys.find(name, id)
            raise WebAuthn::Error, "unregistered credential" unless found
            [name, found]
        end
    end
end
