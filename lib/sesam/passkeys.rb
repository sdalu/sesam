# frozen_string_literal: true

module Sesam
    # The passkeys each user registered (WebAuthn), in the database: the
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
        Registered = Data.define(:id, :user, :public_key, :sign_count,
                                 :label, :created_at)

        def initialize(db)
            @db = db
        end

        # A user's passkeys, oldest first.
        def of(name)
            rows.where(user: name.to_s).order(:created_at, :id).all
                .map { entry(it) }
        end

        def find(name, id)
            row = rows.where(user: name.to_s, id: id.to_s).first
            row && entry(row)
        end

        # Whose credential `id` is, or nil.
        def owner_of(id) = rows.where(id: id.to_s).get(:user)

        # Registered again, an id replaces its record.
        def add(name, id:, public_key:, sign_count:, label:)
            @db.transaction do
                rows.where(id:).delete
                rows.insert(id:, user: name, public_key:,
                            sign_count: sign_count.to_i, label:,
                            created_at: Time.now)
            end
        end

        # The passkeys `name` keeps afterwards.
        def remove(name, id)
            rows.where(user: name.to_s, id: id.to_s).delete
            of(name)
        end

        # After an assertion: never creates one, since a credential not
        # registered was refused before this.
        def seen(name, id, sign_count)
            rows.where(user: name.to_s, id: id.to_s)
                .update(sign_count: sign_count.to_i)
        end

        private

        def rows = @db[:passkeys]

        def entry(row) = Registered.new(**row.slice(*Registered.members))
    end
end
