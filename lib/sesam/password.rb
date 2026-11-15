# frozen_string_literal: true

require "base64"
require "openssl"
require "securerandom"

module Sesam
    # A password as it is kept: scrypt from OpenSSL (no gem), its cost
    # and salt written beside the hash so that a later cost still
    # checks an older one. Never kept, logged or shown in clear.
    module Password
        # 2^14 rounds of 8 blocks: 16 MiB and some tens of
        # milliseconds a check, on a small ARM board too.
        COST = { N: 2**14, r: 8, p: 1 }.freeze
        LENGTH = 32
        # The least length a password may have.
        SHORTEST = 12

        module_function

        # The hash to keep: scrypt$N$r$p$SALT$HASH.
        def digest(password, cost: COST)
            salt = SecureRandom.bytes(16)
            hash = derive(password, salt, cost)
            ["scrypt", cost[:N], cost[:r], cost[:p], encode(salt),
             encode(hash)].join("$")
        end

        # Whether `password` is the one `kept` was made from; false for
        # nothing kept. Compared in constant time.
        def match?(password, kept)
            kind, n, r, p, salt, hash = kept.to_s.split("$")
            return false unless kind == "scrypt" && hash
            cost = { N: Integer(n), r: Integer(r), p: Integer(p) }
            OpenSSL.secure_compare(
                encode(derive(password, decode(salt), cost)), hash
            )
        rescue ArgumentError
            false
        end

        # What is wrong with `password` as a new one, or nil.
        def refusal(password)
            text = password.to_s
            return "a password is #{SHORTEST} characters at least" if
                text.length < SHORTEST
            "a password has no control characters" if
                text.match?(/[[:cntrl:]]/)
        end

        def derive(password, salt, cost)
            OpenSSL::KDF.scrypt(password.to_s, salt:, length: LENGTH,
                                               **cost)
        end

        def encode(bytes) = Base64.strict_encode64(bytes)
        def decode(text) = Base64.strict_decode64(text)
    end
end
