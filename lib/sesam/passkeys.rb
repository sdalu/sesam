# frozen_string_literal: true

module Sesam
    # The passkeys each user registered (WebAuthn), in the store: the
    # public half of each device's key pair, by its credential id. What is
    # kept signs nothing; the private half never leaves the authenticator.
    #
    # `sign_count` is the authenticator's own counter, kept as the
    # specification asks: one going backwards means two authenticators
    # answer for one credential. Synced passkeys report zero forever, so
    # it is recorded rather than judged. `label` is the person's own name
    # for the device, the one thing in a record they can act on ("which
    # of these is the phone I lost").
    class Passkeys
        # A credential id another user holds.
        class Error < Sesam::Error; end

        TABLE = :passkeys

        Registered = Data.define(:id, :user, :public_key, :sign_count,
                                 :label, :created_at)

        def initialize(store)
            @store = Sesam.store!(store)
        end

        # A user's passkeys, oldest first.
        def of(name)
            @store.all(TABLE, order: %i[created_at id], user: name.to_s)
                  .map { entry(it) }
        end

        def find(name, id)
            row = @store.first(TABLE, user: name.to_s, id: id.to_s)
            row && entry(row)
        end

        # Whose credential `id` is, or nil.
        def owner_of(id) = @store.first(TABLE, id: id.to_s)&.[](:user)

        # Registered again by its owner, an id replaces its record;
        # Error for one another user holds (WebAuthn: a credential id is
        # refused when already registered), which would take theirs.
        def add(name, id:, public_key:, sign_count:, label:)
            @store.transaction do
                name = user!(name)
                held = owner_of(id)
                if held && held != name.to_s
                    raise Error, "credential #{id} is another user's"
                end
                @store.delete(TABLE, id:)
                @store.insert(TABLE, row(name, id, public_key, sign_count,
                                         label))
            end
        end

        # Every passkey of `name` gone (a lost device, a reset); how many.
        def clear(name) = @store.delete(TABLE, user: name.to_s)

        # The passkeys `name` keeps afterwards.
        def remove(name, id)
            @store.delete(TABLE, user: name.to_s, id: id.to_s)
            of(name)
        end

        # After an assertion: never creates one, since a credential not
        # registered was refused before this.
        def seen(name, id, sign_count)
            @store.update(TABLE, { sign_count: sign_count.to_i },
                          user: name.to_s, id: id.to_s)
        end

        private

        # `name` as kept, a String; Error for a name no user has, whose
        # passkey a user added later under it would inherit (a store need
        # not hold a foreign key).
        def user!(name)
            raise Error, "no user #{name}" unless
                @store.count(:users, name: name.to_s).positive?
            name.to_s
        end

        # The row of `name`'s passkey `id`, registered now.
        def row(name, id, public_key, sign_count, label)
            { id:, user: name, public_key:, sign_count: sign_count.to_i,
              label:, created_at: Stamp.ms(Time.now) }
        end

        def entry(row)
            Registered.new(**Stamp.times(row.slice(*Registered.members),
                                         :created_at))
        end
    end
end
