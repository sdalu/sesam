# frozen_string_literal: true

require "json"
require "openssl"
require "rack/test"

require "test_helper"
require "sesam/passkey"
require "sesam/sinatra"
# fake_client reaches for Forwardable without requiring it.
require "forwardable"
require "webauthn/fake_client"

# What the gate's and the routes' tests share: a database holding alice
# and bruno, each with their key (ALICE, BRUNO); addresses from the
# documentation ranges (RFC 5737) and names under example.org; and an
# application as small as sesam allows, whose hooks write down what they
# were told.
module WebSupport
    include Rack::Test::Methods

    ALICE    = "alice-0123456789abcdef0123456789abcdef"
    BRUNO    = "bruno-fedcba9876543210fedcba9876543210"
    SECRET   = "s" * 40
    LAN      = "192.0.2.10"
    WAN      = "203.0.113.7"
    HOST     = "app.example.org"
    ORIGIN   = "https://#{HOST}".freeze
    PASSWORD = "a long enough password"

    def setup
        @db = Sequel.sqlite
        Sesam.migrate(@db)
        { "alice" => ALICE, "bruno" => BRUNO }.each { keyed(*it) }
        @told = []
        @profiles = {}
    end

    def users = Sesam::Users.new(@db)

    # `name` added, with `key` as theirs: put in as Users#key keeps one
    # (its digest), since that makes up its own.
    def keyed(name, key)
        users.add(name)
        @db[:user_keys].insert(
            user: name, digest: OpenSSL::Digest.hexdigest("SHA256", key),
            created_at: Sesam::Stamp.ms(Time.now)
        )
    end

    # The LAN this suite trusts: loopback and 192.0.2.0/24.
    def settings(**given)
        Sesam::Settings.new(
            database: ->(&block) { block.call(@db) }, app: "app",
            lan: ["127.0.0.0/8", "192.0.2.0/24"], session:,
            passkey: Sesam::Passkey.new(ORIGIN), **given
        )
    end

    def session = Sesam::Session.new(SECRET, lifetime: 3600)

    def access(**) = settings(**).access

    # A request from `peer`, as Rack hands it over.
    def from(peer, **headers)
        { "REMOTE_ADDR" => peer, "HTTP_HOST" => HOST }.merge(headers)
    end

    def cookie_env(name)
        value = session.cookie_for(name, "/")[:value]
        { "HTTP_COOKIE" => "sesam_session=#{value}" }
    end

    # Built once a test, with the settings it gave (@given).
    def app
        @app ||= TestApp.build(settings(**@given.to_h), @told, @profiles)
    end

    # A call as a browser makes it, over https, from off the LAN unless
    # said; the status.
    def call(verb, path, body = nil, peer: WAN, **headers)
        send(verb, "https://#{HOST}#{path}", body && JSON.generate(body),
             from(peer, "CONTENT_TYPE" => "application/json", **headers))
        last_response.status
    end

    def reply = JSON.parse(last_response.body)

    def signed_in_as_alice
        users.password!("alice", PASSWORD)
        call(:post, "/session/password", { name: "alice", password: PASSWORD })
    end

    # The application: sesam's routes, a route behind the gate (GET
    # /secret, answering who), and the hooks.
    module TestApp
        def self.build(sesam, told, profiles)
            Class.new(Sinatra::Base) do
                register Sesam::Sinatra
                set :sesam, sesam
                TestApp.settings(self)
                TestApp.gate(self)
                get("/secret") { answer({ who: }) }
                TestApp.hooks(self, told, profiles)
            end
        end

        # Any host, errors raised. Sinatra's JSON CSRF guard refuses a
        # cross-site read of JSON by itself (a request with no Referer):
        # off here, so that what these tests see of a cross-site request
        # is sesam's gate.
        def self.settings(app)
            app.set :host_authorization, { permitted_hosts: [] }
            app.set :show_exceptions, false
            app.set :raise_errors, true
            app.set :protection, except: :json_csrf
        end

        # The gate as an application sets it: cross-site writes, then
        # who is calling, but on the routes open to all.
        def self.gate(app)
            app.before do
                same_site!
                admit! unless sesam_open?
            end
        end

        def self.hooks(app, told, profiles)
            app.define_method(:sesam_changed) do |name, db|
                told << [:changed, name, db.in_transaction?]
            end
            app.define_method(:sesam_notify) do |name, kind|
                told << [:notify, name, kind]
            end
            app.define_method(:sesam_profile) { profiles.fetch(it, {}) }
            recovery(app, told, profiles)
        end

        # A user by their email (a profile's :email), and a link mailed
        # to whoever has one.
        def self.recovery(app, told, profiles)
            app.define_method(:sesam_named) do |text|
                profiles.find { |_, profile| profile[:email] == text }&.first
            end
            app.define_method(:sesam_asked) do |name, db|
                told << [:asked, name, db.in_transaction?]
            end
            app.define_method(:sesam_reached?) do |name, token|
                told << [:invited, name, token]
                !profiles.dig(name, :email).nil?
            end
        end
    end
end
