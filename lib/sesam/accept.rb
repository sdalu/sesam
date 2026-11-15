# frozen_string_literal: true

module Sesam
    # What a caller may present: a program's key, a browser's passkey or
    # password, each accepted unless left out. The key is the gate's
    # (Access, Credential), a passkey's and a password's their routes'
    # (sesam/sinatra), and the browser's ways (SIGN_IN) what a sign-in
    # screen offers, told it in a 401.
    class Accept
        # None, or a word not in ALL.
        class Error < Sesam::Error; end

        ALL = %w[key passkey password].freeze
        # The ways a browser signs in, in the order a screen offers them.
        SIGN_IN = %w[password passkey].freeze

        # given: some of ALL; none, or another word, is refused.
        def initialize(given = ALL)
            ways = Array(given).map(&:to_s).uniq
            unless ways.any? && (ways - ALL).empty?
                raise Error, "accept: any of #{ALL.join(", ")}"
            end
            @ways = ways.freeze
            freeze
        end

        def to_a = @ways

        def include?(way) = @ways.include?(way)

        # The browser's ways accepted, SIGN_IN's order.
        def sign_in = SIGN_IN & @ways
    end
end
