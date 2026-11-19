# frozen_string_literal: true

require "sesam/version"
require "sesam/password"
require "sesam/stamp"
require "sesam/session"
require "sesam/forwarded"
require "sesam/throttle"
require "sesam/spent"

# Who may use a small Rack application, and how they prove it
# (README.md): passwords kept as scrypt hashes, sessions as signed
# cookies, the caller behind trusted proxies read from Forwarded, and
# failures counted over a window; users, their keys, invitations,
# LAN addresses and passkeys kept in a store, the application's
# database wrapped or a file of its own.
module Sesam
    # What sesam refuses, whatever the piece.
    class Error < StandardError; end

    # What every store answers to.
    STORE = %i[all first count insert update delete transaction
               rollback! in_transaction?].freeze

    # `given` as a store; Error for anything else, a database given
    # bare among them: wrapped, it is a store, never silently.
    def self.store!(given)
        return given if STORE.all? { given.respond_to?(it) }
        raise Error, "not a store: a Sequel database is given as " \
                     "Sesam::SequelStore.new(db)"
    end
end

require "sesam/store"
require "sesam/schema"
require "sesam/sequel_store"
require "sesam/json_store"
require "sesam/users"
require "sesam/passkeys"
require "sesam/networks"
require "sesam/accept"
require "sesam/credential"
require "sesam/access"
require "sesam/settings"
