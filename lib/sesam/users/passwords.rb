# frozen_string_literal: true

require "sesam/password"

module Sesam
    class Users
        # A user's password, kept as its scrypt hash (Password): set,
        # removed, and checked in the time a real check takes, for a
        # name unknown too.
        module Passwords
            def password!(name, password)
                name = found!(name)
                refusal = Password.refusal(password)
                raise Error, refusal if refusal
                @store.update(:users, { password: Password.digest(password) },
                              name:)
            end

            # `name`'s password gone, even their last way in: sessions are
            # left to the caller to end. Nothing to check, a password not
            # being set.
            def unpassword!(name)
                name = found!(name)
                @store.update(:users, { password: nil }, name:)
            end

            def password?(name) = !get(:users, :password, name: name.to_s).nil?

            # Whether `password` is `name`'s; false for no such user or no
            # password, after as much work as a real check.
            def password_match?(name, password)
                kept = get(:users, :password, name: name.to_s)
                return Password.match?(password, DECOY) && false unless kept
                Password.match?(password, kept)
            end

            # What an unknown name is checked against, so that it takes the
            # time a known one does.
            DECOY = Password.digest("not a password, ever")
            private_constant :DECOY
        end
    end
end
