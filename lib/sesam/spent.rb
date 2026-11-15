# frozen_string_literal: true

module Sesam
    # Challenges spent, remembered until they would have lapsed anyway: a
    # ceremony's challenge rides in a signed cookie the client holds, so
    # dropping the cookie spends it for an honest client only, and one
    # who kept it could replay the same answer (a synced passkey's
    # counter stays at 0 and cannot tell). In memory, as Throttle: one
    # process serves, and a restart forgets only what lapses within the
    # window.
    class Spent
        def initialize(window:)
            @window = window
            @seen   = {}
            @lock   = Mutex.new
        end

        # Whether `value` was not spent yet; spent from now on.
        def spend!(value, now: Time.now)
            @lock.synchronize do
                @seen.delete_if { |_, at| now - at > @window }
                next false if @seen.key?(value)
                @seen[value] = now
                true
            end
        end
    end
end
