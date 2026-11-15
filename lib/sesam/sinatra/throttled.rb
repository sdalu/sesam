# frozen_string_literal: true

module Sesam
    module Sinatra
        # Failures counted (Settings#throttle) by name and address
        # together and by address, never by name alone: a name alone
        # would let anyone knowing it keep its owner out from elsewhere.
        # Behind trusted proxies the address is the client they
        # forwarded (Access#client).
        module Throttled
            # Failures a window: a name from one address, any name from
            # one address.
            BY_TRY = 5
            BY_PEER = 20

            def sign_in_throttled!(name)
                throttle = sesam.throttle
                tried = throttle.blocked?(try_key(name), BY_TRY)
                from = throttle.blocked?(peer_key, BY_PEER)
                too_many! if tried || from
            end

            def too_many!
                refuse(429, "too many tries: wait a quarter of an hour")
            end

            def sign_in_failed!(name, message)
                sesam.throttle.failed!(try_key(name))
                sesam.throttle.failed!(peer_key)
                refuse(403, message)
            end

            # A name that is no user's name is counted as one, so that
            # the body cannot make keys of any length.
            def try_key(name)
                tried = Users::NAME.match?(name) ? name : "?"
                "try:#{tried}@#{sign_in_peer}"
            end

            def peer_key = "peer:#{sign_in_peer}"

            # The client counted: behind a trusted proxy, the one it
            # forwarded (Access#client).
            def sign_in_peer = sesam.access.client(request.env)
        end
    end
end
