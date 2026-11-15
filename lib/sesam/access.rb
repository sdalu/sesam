# frozen_string_literal: true

module Sesam
    # Who may use the application, decided in one place, from the caller
    # (#client): the socket peer (REMOTE_ADDR, which Rack fills from the
    # socket and a client cannot set), or, when that peer is a proxy
    # trusted to say whom it forwards (Settings#proxy?), the caller the
    # proxies' Forwarded header names, read from the right past each of
    # them. A client writes only to the left of what they add, so no
    # header of theirs claims a LAN address; X-Forwarded-For is never
    # read.
    #
    # Four answers. A credential, when the request bears a key or a
    # session (Credential): admitted under its name, LAN or not, so that
    # an audit says who. Else a caller on the LAN and no proxy: admitted
    # without one, as "lan:ADDR", or as the user known at that address.
    # Else the application asking itself (Settings#internal): an env key
    # no request sets. Else refused, which is where a caller off the LAN
    # with nothing, or a wrong key, ends: fail closed.
    #
    # Which name is asked for is another question, the Host header's,
    # left to the application's host authorization: under DNS rebinding
    # the peer really is on the LAN, a remote page driving the visitor's
    # own browser.
    class Access
        PEER = "REMOTE_ADDR"

        # user: the user the caller is, by a key, a session or a LAN
        # address they are known at (Users#address!); nil for none.
        Caller = Data.define(:verdict, :name, :user) do
            def initialize(verdict:, name:, user: nil) = super
            def refused? = verdict == :refused
        end

        def initialize(settings)
            @settings = settings
            @credential = Credential.new(settings)
            freeze
        end

        # The verdict and the name together, from one walk of the rules:
        # asked separately, they could disagree.
        def caller_for(env)
            name = @credential.name_for(env)
            return Caller.new(verdict: :credential, name:, user: name) if name
            caller = client(env)
            return lan(caller) if lan?(caller)
            internal(env[@settings.internal]) ||
                Caller.new(verdict: :refused, name: nil)
        end

        def allow?(env) = !caller_for(env).refused?

        # The client a request comes from, who is admitted on the LAN and
        # whose failures are counted: the socket peer; when that peer is
        # a trusted proxy, the Forwarded `for` nearest the right that is
        # no proxy, each trusted proxy adding its own caller there (RFC
        # 7239) and a client able to write only to their left; when every
        # one is a proxy, the leftmost, which is never admitted on the
        # LAN.
        def client(env)
            peer = Networks.canonical(env[PEER])
            return peer unless @settings.proxy?(peer)
            hops = Forwarded.fors(env["HTTP_FORWARDED"])
                            .map { Networks.canonical(it) }
            hops.reverse.find { !@settings.proxy?(it) } || hops.first || peer
        end

        private

        # The application asking itself, under its name; nil for a
        # request that is not.
        def internal(name)
            name && Caller.new(verdict: :lan, name: "#{@settings.app}:#{name}")
        end

        # On the LAN, an address, and no proxy: a proxy forwards others.
        def lan?(caller)
            address?(caller) && @settings.lan?(caller) &&
                !@settings.proxy?(caller)
        end

        # A LAN caller: named for the user known at the address, if any.
        # A name, not a proof: what a user does to their own way in still
        # wants a key or a session.
        def lan(caller)
            user = @credential.user_at(caller)
            Caller.new(verdict: :lan, name: user || "lan:#{caller}", user:)
        end

        def address?(text) = !Networks.address(text).nil?
    end
end
