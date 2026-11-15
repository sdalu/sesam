# frozen_string_literal: true

module Sesam
    # What an application tells sesam, in one place: where its users are
    # (`database`, a callable yielding a Sequel database to its block),
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

        # Each setting but `database`, as it is unless given.
        DEFAULTS = { lan: [], proxies: [], accept: Accept::ALL, mount: "",
                     session: nil, passkey: nil, throttle: nil,
                     reserved: [], app: "sesam" }.freeze

        # ceremonies: the challenges spent (Spent), each until it would
        # have lapsed.
        attr_reader :accept, :mount, :session, :passkey, :throttle,
                    :ceremonies,
                    :reserved, :app, :access

        # given: DEFAULTS' keys; another is refused. throttle: a
        # quarter of an hour's unless given. passkey: kept only where
        # passkeys are accepted, and refused without a session (a passkey
        # signs in to a session).
        def initialize(database:, **given)
            @database = callable!(database)
            set = settings!(given)
            network!(set)
            ways!(set)
            @access = Access.new(self)
            freeze
        end

        # The database, given to the block.
        def database(&) = @database.call(&)

        # Users and Passkeys in `db`.
        def users_in(db) = Users.new(db, reserved: @reserved)
        def passkeys_in(db) = Passkeys.new(db)

        # Users, given to the block, in the database.
        def with_users = database { yield users_in(it) }

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

        def settings!(given)
            unknown = given.keys - DEFAULTS.keys
            return DEFAULTS.merge(given) if unknown.empty?
            raise Error, "not a setting: #{unknown.join(", ")}"
        end

        def accept_of(given) = given.is_a?(Accept) ? given : Accept.new(given)

        def callable!(database)
            return database if database.respond_to?(:call)
            raise Error, "database: a callable yielding a Sequel database"
        end

        def passkey_of(passkey)
            return nil unless passkey && @accept.include?("passkey")
            return passkey if @session
            raise Error, "passkey: passkeys end in a session, and there " \
                         "is no session"
        end
    end
end
