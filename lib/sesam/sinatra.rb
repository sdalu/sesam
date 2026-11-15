# frozen_string_literal: true

begin
    require "sinatra/base"
rescue LoadError
    raise LoadError, "sesam/sinatra needs the sinatra gem: add it to the " \
                     "application's Gemfile"
end

require "sesam"
require "sesam/sinatra/replies"
require "sesam/sinatra/gate"
require "sesam/sinatra/throttled"
require "sesam/sinatra/sessions"
require "sesam/sinatra/passkeys"
require "sesam/sinatra/invitations"
require "sesam/sinatra/recovery"

module Sesam
    # The sign-in routes and the gate's helpers, as a Sinatra extension:
    # `register Sesam::Sinatra` in the application, `set :sesam,` its
    # Settings, and `same_site!` then `admit! unless sesam_open?` in a
    # before filter.
    #
    # What the application may define, else sesam's default is used
    # (Replies, Hooks): `answer`, `refuse` (raising: a refusal must roll
    # back the transaction it crosses), `parsed_body`, and the hooks
    # `sesam_changed(name, db)` (in the transaction where a user changed
    # their way in), `sesam_notify(name, kind)` (after it, :password or
    # :passkey) and `sesam_profile(name)` (a Hash merged into what
    # GET /session and an invitation's check answer). A method the
    # application already has is never replaced, whichever comes first.
    module Sinatra
        # What a caller reaches without being admitted: signing in is
        # what a browser with no session does, and one whose session
        # lapsed must still be able to drop it.
        OPEN = [%w[POST /session/challenge], %w[POST /session],
                %w[POST /session/password], %w[POST /session/invite/check],
                %w[POST /session/invite], %w[POST /session/invite/challenge],
                %w[POST /session/invite/passkey], %w[POST /session/recover],
                %w[DELETE /session]].freeze

        def self.registered(app)
            app.set :sesam, nil unless app.respond_to?(:sesam)
            app.helpers(missing(app, Replies), missing(app, Hooks))
            app.helpers Gate
            app.error(Refused) { refusal(env["sinatra.error"]) }
            [Sessions, Passkeys, Invitations, Recovery].each do |part|
                app.register part
            end
        end

        # What an answer to a passkey that does not verify is: WebAuthn's
        # error, which exists only where sesam/passkey was loaded.
        def self.unverified
            defined?(::WebAuthn::Error) ? [::WebAuthn::Error] : []
        end

        # `defaults`' methods the app does not have yet, as a module.
        def self.missing(app, defaults)
            methods = defaults.instance_methods(false).reject do |name|
                app.method_defined?(name) || app.private_method_defined?(name)
            end
            Module.new do
                methods.each { define_method(it, defaults.instance_method(it)) }
            end
        end
    end
end
