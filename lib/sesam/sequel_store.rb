# frozen_string_literal: true

require "sequel"

module Sesam
    # sesam's tables in the application's Sequel database, migrated by
    # Sesam.migrate: the store a host on Sequel gives (`#db` returns its
    # database, for a hook writing in the same transaction). A
    # transaction opened inside another joins it, as Sequel's do.
    class SequelStore
        # sesam's tables, the only ones a store reads or writes.
        TABLES = %i[users user_keys user_addresses invites passkeys].freeze

        # The tables whose rows the store numbers (`insert` returns it).
        NUMBERED = %i[user_keys invites].freeze

        attr_reader :db

        def initialize(db)
            unless db.is_a?(::Sequel::Database)
                raise Error, "SequelStore: a Sequel database, not " \
                             "#{db.class}"
            end
            @db = db
            # On SQLite a transaction takes the write lock as it begins:
            # one taking it only at its first write fails to upgrade
            # while another holds it, where it should have waited (two
            # adding a name at once).
            @begin = db.database_type == :sqlite ? { mode: :immediate } : {}
        end

        # A nil sorts first, whichever database orders it.
        def all(table, order: [], **equal)
            rows(table, equal)
                .order(*order.map { ::Sequel.asc(it, nulls: :first) }).all
        end

        def first(table, **equal) = rows(table, equal).first
        def count(table, **equal) = rows(table, equal).count

        def insert(table, row)
            id = rows(table, {}).insert(row)
            NUMBERED.include?(table) ? id : nil
        end

        def update(table, changes, **equal) = rows(table, equal).update(changes)
        def delete(table, **equal) = rows(table, equal).delete

        # A rollback! anywhere inside, in a joined transaction too, undoes
        # the outermost one, which answers nil: Sequel's Rollback, raised
        # through the joined blocks, is caught by Sequel's outermost.
        def transaction
            @db.transaction(**@begin) do
                yield
            rescue Rollback
                raise ::Sequel::Rollback
            end
        end

        def in_transaction? = @db.in_transaction?

        def rollback!
            raise Error, "rollback! outside a transaction" unless
                in_transaction?
            raise Rollback
        end

        private

        def rows(table, equal)
            raise Error, "no table #{table.inspect} in a store" unless
                TABLES.include?(table)
            @db[table].where(equal)
        end
    end
end
