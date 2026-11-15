# frozen_string_literal: true

module Sesam
    # Failures counted per key over a window (a name tried from one
    # client, a client, a client looking up invitations): past the
    # limit the caller names, refused until the oldest failure falls
    # out of the window. Never a name alone: anyone knowing a name
    # could then keep its owner out from elsewhere. In memory, so for
    # an application served by one process (puma's `workers 0`): a
    # restart forgetting the count costs a guesser one window. Only keys
    # with failures still in the window are kept, so that asking about
    # anything else costs nothing; when there are many, every stale
    # one goes.
    class Throttle
        # Keys past which a failure sweeps out every stale one.
        SWEEP = 1000

        def initialize(window:)
            @window = window
            @hits   = {}
            @lock   = Mutex.new
        end

        def blocked?(key, limit, now: Time.now)
            @lock.synchronize { recent(key, now).size >= limit }
        end

        def failed!(key, now: Time.now)
            @lock.synchronize do
                sweep(now) if @hits.size >= SWEEP
                @hits[key] = recent(key, now) << now
            end
        end

        def clear!(key) = @lock.synchronize { @hits.delete(key) }

        # How many keys are kept.
        def size = @lock.synchronize { @hits.size }

        private

        # The key's failures in the window; the key forgotten when
        # none is left.
        def recent(key, now)
            kept = (@hits[key] || []).reject { now - it > @window }
            kept.empty? ? @hits.delete(key) : @hits[key] = kept
            kept
        end

        def sweep(now) = @hits.each_key.to_a.each { recent(it, now) }
    end
end
