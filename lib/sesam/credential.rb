# frozen_string_literal: true

module Sesam
    # What admits a caller off the LAN: a user (Users), named by an API
    # key the request bears (`Authorization: Bearer KEY`, a program's
    # way) or by the session a browser holds (Session, left by a
    # password, a passkey or an invitation), as long as that user still
    # exists and has not ended their sessions since: removing one ends
    # their sessions at the next request.
    #
    # A key is looked up by its digest, not compared: what is kept is
    # SHA-256 of 256 random bits, so the lookup tells a guesser nothing a
    # guess would not.
    class Credential
        BEARER = /\ABearer\s+(\S+)\z/

        def initialize(settings)
            @settings = settings
            freeze
        end

        # The user the request's key is, else the user its session names;
        # nil. A key in the query string is never read: a link must not
        # act; nor one in the header where keys are not accepted.
        def name_for(env)
            key = key_in(env)
            held = @settings.session&.held_from(env)
            return nil unless key || held
            @settings.with_users { found(it, key, held) }
        end

        # The user known at the LAN address `peer`, or nil.
        def user_at(peer) = @settings.with_users { it.address_owner(peer) }

        private

        def key_in(env)
            return nil unless @settings.accept.include?("key")
            env["HTTP_AUTHORIZATION"].to_s[BEARER, 1]
        end

        def found(users, key, held)
            owner = key && users.key_owner(key)
            return owner if owner
            held.name if held && users.session_valid?(held.name, held.issued)
        end
    end
end
