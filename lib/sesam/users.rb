# frozen_string_literal: true

require "openssl"
require "securerandom"

require "sesam/password"
require "sesam/users/passwords"
require "sesam/users/invitations"
require "sesam/users/account"

module Sesam
    # Who may use the application, kept in a store (Sesam.store!, the
    # tables of Sesam.migrate): a user is a name, their login, who signs
    # in with a password or a passkey set through an invitation (a
    # single-use link, Users#invite), or sends an API key (Users#key).
    # Neither a key nor an invitation is kept: only its SHA-256 digest,
    # enough to recognise it (both are 256 random bits, so a fast digest
    # loses nothing) and useless to present.
    #
    # What the application knows of a person besides (names to greet
    # them by, an address to mail) is the application's, in a table of
    # its own keyed by the user; names it keeps for itself (an audit's
    # `root`) are refused (`reserved`).
    class Users
        class Error < Sesam::Error; end

        NAME = /\A[a-z0-9][a-z0-9_.-]{0,31}\z/i

        Key = Data.define(:id, :user, :label, :created_at)
        include Invitations
        include Passwords
        include Account

        # What is a user's, gone with them (#remove).
        OWNED = %i[user_keys user_addresses invites passkeys].freeze

        Row = Data.define(:name, :password, :created_at, :keys, :passkeys,
                          :invite, :addresses)

        # reserved: names no user may take, whatever their case;
        # strings or symbols.
        def initialize(store, reserved: [])
            @store = Sesam.store!(store)
            @reserved = reserved.map { it.to_s.downcase }.freeze
        end

        # `name` as a user's name; Error for one malformed or reserved.
        def self.name!(name, reserved: [])
            text = name.to_s
            unless NAME.match?(text)
                raise Error, "bad user name #{text.inspect}: letters, " \
                             "digits, _ . - (32 at most)"
            end
            raise Error, "#{text} is reserved" if
                reserved.include?(text.downcase)
            text
        end

        def exists?(name) = @store.count(:users, name: name.to_s).positive?

        def names = @store.all(:users, order: [:name]).map { it[:name] }

        def any? = @store.count(:users).positive?

        # A name is refused when it differs from a user's by case alone:
        # two such would be told apart by nobody reading an audit, and a
        # database comparing without case would take one for the other.
        def add(name, now: Time.now)
            name = Users.name!(name, reserved: @reserved)
            @store.transaction do
                free!(name)
                @store.insert(:users, { name:, created_at: Stamp.ms(now),
                                        sessions_since: Stamp.ms(now) })
            end
            name
        end

        # The user gone, and with them their keys, invitations, passkeys
        # and sessions (whoever reads a session asks whether its name
        # exists). Taken here, in one transaction: a store need not
        # cascade.
        def remove(name)
            name = found!(name)
            @store.transaction do
                OWNED.each { @store.delete(it, user: name) }
                @store.delete(:users, name:)
            end
        end

        # Each user: password set or not, keys, passkeys, an invitation
        # open (its expiry), nil for none.
        def list(now: Time.now)
            @store.all(:users, order: [:name]).map { row_of(it, now) }
        end

        # --- API keys -----------------------------------------------

        # A new key for `name`: shown once, never again.
        def key(name, label: nil, now: Time.now)
            secret = SecureRandom.urlsafe_base64(36)
            @store.transaction do
                name = found!(name)
                @store.insert(:user_keys, { user: name, digest: digest(secret),
                                            label:, created_at: Stamp.ms(now) })
            end
            secret
        end

        def keys_of(name)
            name = found!(name)
            @store.all(:user_keys, order: [:id], user: name).map do |row|
                Key.new(**Stamp.times(row.slice(*Key.members), :created_at))
            end
        end

        def unkey(name, id)
            gone = @store.delete(:user_keys, user: name.to_s, id: Integer(id))
            raise Error, "#{name} has no key #{id}" if gone.zero?
        rescue ArgumentError
            raise Error, "a key's id is a number: #{id}"
        end

        # Whose key `secret` is, or nil.
        def key_owner(secret)
            return nil if secret.to_s.empty?
            get(:user_keys, :user, digest: digest(secret))
        end

        private

        def row_of(row, now)
            name = row[:name]
            Row.new(**Stamp.times(row.slice(:name, :created_at), :created_at),
                    password: !row[:password].nil?,
                    keys: @store.count(:user_keys, user: name),
                    passkeys: @store.count(:passkeys, user: name),
                    invite: Stamp.time(open_invites(name, now).first
                                       &.[](:expires_at)),
                    addresses: addresses_of(name))
        end

        # No user's name is `name` whatever its case; checked in the
        # transaction that adds it, so of two adding it at once one is
        # refused (a store need not hold a key on the name).
        def free!(name)
            taken = @store.all(:users).map { it[:name] }
                          .find { it.downcase == name.downcase }
            raise Error, "user #{taken} exists already" if taken
        end

        # `name` as the String it is kept as; Error for no such user. A
        # Symbol written as it is would match nothing in a file, and name
        # a column in SQL.
        def found!(name)
            raise Error, "no user #{name}" unless exists?(name)
            name.to_s
        end

        def digest(secret) = OpenSSL::Digest.hexdigest("SHA256", secret.to_s)

        # `column` of the first row `equal` matches, nil for none.
        def get(table, column, **equal)
            @store.first(table, **equal)&.[](column)
        end
    end
end
