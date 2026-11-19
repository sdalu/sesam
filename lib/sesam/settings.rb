# frozen_string_literal: true

module Sesam
    # What an application tells sesam, in one place: where its users are
    # (`store`, a store or a callable yielding one to its block),
    # its trusted networks (`lan`) and proxies (`proxies`, each a list
    # or Networks), what a caller
    # may present (`accept`), the cookie path (`mount`), the Session and
    # Passkey it made, the Throttle counting failures, the names no user
    # may take (`reserved`), and the application's name (`app`), which
    # names the realm of a 401, its sign-in header, and the requests it
    # makes to itself.
    class Settings
        # A setting no gate could work with.
        class Error < Sesam::Error; end

        # Each setting but `store`, as it is unless given.
        DEFAULTS = { lan: [], proxies: [], accept: Accept::ALL, mount: "",
                     session: nil, passkey: nil, throttle: nil,
                     reserved: [], app: "sesam", reset_passkeys: "keep",
                     recovery: false, recovery_for: 3600 }.freeze

        # What a reset by invitation does to the passkeys a user had and
        # their other sessions: keep (passkeys kept, sessions ended),
        # drop (both gone), drop_keep_sessions (the passkeys alone).
        RESETS = %w[keep drop drop_keep_sessions].freeze

        # ceremonies: the challenges spent (Spent), each until it would
        # have lapsed.
        attr_reader :accept, :mount, :session, :passkey, :throttle,
                    :ceremonies, :reset_passkeys, :recovery, :recovery_for,
                    :reserved, :app, :access

        # given: DEFAULTS' keys; another is refused. throttle: a
        # quarter of an hour's unless given. passkey: kept only where
        # passkeys are accepted, and refused without a session (a passkey
        # signs in to a session).
        def initialize(store:, **given)
            @store = store_of(store)
            set = settings!(given)
            network!(set)
            ways!(set)
            recovery!(set)
            @access = Access.new(self)
            freeze
        end

        # The store, given to the block.
        def store(&) = @store.call(&)

        # Users and Passkeys in `store`.
        def users_in(store) = Users.new(store, reserved: @reserved)
        def passkeys_in(store) = Passkeys.new(store)

        # Users, given to the block, in the store.
        def with_users = store { yield users_in(it) }

        def lan?(address) = @lan.include?(address)

        # Whether `address` is a proxy trusted to say whom it forwards.
        def proxy?(address) = @proxies.include?(address)

        # What a 401 carries: WWW-Authenticate, and the header naming the
        # browser's ways in (X-App-Sign-In).
        def realm = %(Bearer realm="#{@app}")
        def sign_in_header = "X-#{@app.capitalize}-Sign-In"

        # The env key the application's own requests carry (set by no
        # HTTP request, a header becoming HTTP_*).
        def internal = Settings.internal(@app)

        # The env key of `app`'s own requests, for what makes them.
        def self.internal(app) = "#{app}.internal"

        private

        # Who is where: the LAN, the proxies, the application's name.
        def network!(set)
            @lan     = Networks.of(set[:lan], "lan")
            @proxies = Networks.of(set[:proxies], "proxies")
            @app     = set[:app].to_s
            @reserved = set[:reserved].dup.freeze
        end

        # The ways in, and what keeps a browser's.
        def ways!(set)
            @accept   = accept_of(set[:accept])
            @mount    = set[:mount].to_s
            @session  = set[:session]
            @throttle = set[:throttle] || Throttle.new(window: 900)
            @passkey  = passkey_of(set[:passkey])
            @ceremonies = Spent.new(window: Session::CEREMONY)
        end

        # A reset's effect (RESETS), and whether a link may be asked for
        # from the sign-in screen (recovery, true or false), lasting
        # recovery_for seconds.
        def recovery!(set)
            @reset_passkeys = set[:reset_passkeys].to_s
            unless RESETS.include?(@reset_passkeys)
                raise Error, "reset_passkeys: one of #{RESETS.join(", ")}"
            end
            @recovery = set[:recovery]
            raise Error, "recovery: true or false" unless
                [true, false].include?(@recovery)
            @recovery_for = Integer(set[:recovery_for])
        end

        def settings!(given)
            unknown = given.keys - DEFAULTS.keys
            return DEFAULTS.merge(given) if unknown.empty?
            raise Error, "not a setting: #{unknown.join(", ")}"
        end

        def accept_of(given) = given.is_a?(Accept) ? given : Accept.new(given)

        # A store, as a callable yielding it, the same each time. A
        # database given bare is refused here, not at the first request
        # (it answers `call`, though not as a store's callable).
        def store_of(store)
            if STORE.all? { store.respond_to?(it) }
                return ->(&block) { block.call(store) }
            end
            if store.respond_to?(:call) && !store.respond_to?(:transaction)
                return store
            end
            raise Error, "store: a store, or a callable yielding one; a " \
                         "Sequel database is given as SequelStore.new(db)"
        end

        def passkey_of(passkey)
            return nil unless passkey && @accept.include?("passkey")
            return passkey if @session
            raise Error, "passkey: passkeys end in a session, and there " \
                         "is no session"
        end
    end
end
