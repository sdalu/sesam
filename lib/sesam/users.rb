# frozen_string_literal: true

require "openssl"
require "securerandom"

require "sesam/password"
require "sesam/users/invitations"
require "sesam/users/account"

module Sesam
    # Who may use the application, kept in its database (Sequel, the
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
        include Account

        Row = Data.define(:name, :password, :created_at, :keys, :passkeys,
                          :invite, :addresses)

        # reserved: names no user may take, whatever their case;
        # strings or symbols.
        def initialize(db, reserved: [])
            @db = db
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

        def exists?(name) = !users.where(name: name.to_s).empty?

        def names = users.order(:name).select_map(:name)

        def any? = !users.empty?

        # A name is refused when it differs from a user's by case alone:
        # two such would be told apart by nobody reading an audit, and a
        # database comparing without case would take one for the other.
        def add(name, now: Time.now)
            name = Users.name!(name, reserved: @reserved)
            taken = users.where(Sequel.function(:lower, :name) =>
                                    name.downcase).get(:name)
            raise Error, "user #{taken} exists already" if taken
            users.insert(name:, created_at: Stamp.ms(now),
                         sessions_since: Stamp.ms(now))
            name
        end

        # The user gone, and with them their keys, invitations, passkeys
        # and sessions (whoever reads a session asks whether its name
        # exists).
        def remove(name)
            found!(name)
            users.where(name:).delete
        end

        # Each user: password set or not, keys, passkeys, an invitation
        # open (its expiry), nil for none.
        def list(now: Time.now)
            users.order(:name).all.map { row_of(it, now) }
        end

        # --- passwords ----------------------------------------------

        def password!(name, password)
            found!(name)
            refusal = Password.refusal(password)
            raise Error, refusal if refusal
            users.where(name:).update(password: Password.digest(password))
        end

        # `name`'s password gone, even their last way in: sessions are
        # left to the caller to end. Nothing to check, a password not
        # being set.
        def unpassword!(name)
            found!(name)
            users.where(name:).update(password: nil)
        end

        def password?(name) = !users.where(name:).get(:password).nil?

        # Whether `password` is `name`'s; false for no such user or no
        # password, after as much work as a real check.
        def password_match?(name, password)
            kept = users.where(name: name.to_s).get(:password)
            return Password.match?(password, DECOY) && false unless kept
            Password.match?(password, kept)
        end

        # --- API keys -----------------------------------------------

        # A new key for `name`: shown once, never again.
        def key(name, label: nil, now: Time.now)
            found!(name)
            secret = SecureRandom.urlsafe_base64(36)
            keys.insert(user: name, digest: digest(secret), label:,
                        created_at: Stamp.ms(now))
            secret
        end

        def keys_of(name)
            found!(name)
            keys.where(user: name).order(:id).all.map do |row|
                Key.new(**Stamp.times(row.slice(*Key.members), :created_at))
            end
        end

        def unkey(name, id)
            gone = keys.where(user: name.to_s, id: Integer(id)).delete
            raise Error, "#{name} has no key #{id}" if gone.zero?
        rescue ArgumentError
            raise Error, "a key's id is a number: #{id}"
        end

        # Whose key `secret` is, or nil.
        def key_owner(secret)
            return nil if secret.to_s.empty?
            keys.where(digest: digest(secret)).get(:user)
        end

        private

        # What an unknown name is checked against, so that it takes the
        # time a known one does.
        DECOY = Password.digest("not a password, ever")
        private_constant :DECOY

        def row_of(row, now) # rubocop:disable Metrics/AbcSize
            name = row[:name]
            Row.new(**Stamp.times(row.slice(:name, :created_at), :created_at),
                    password: !row[:password].nil?,
                    keys: keys.where(user: name).count,
                    passkeys: @db[:passkeys].where(user: name).count,
                    invite: Stamp.time(open_invites(name, now)
                                       .get(:expires_at)),
                    addresses: addresses_of(name))
        end

        def found!(name)
            raise Error, "no user #{name}" unless exists?(name)
        end

        def digest(secret) = OpenSSL::Digest.hexdigest("SHA256", secret.to_s)

        def users = @db[:users]
        def keys = @db[:user_keys]
    end
end
