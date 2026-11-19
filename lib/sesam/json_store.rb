# frozen_string_literal: true

require "monitor"

require "sesam/store"
require "sesam/json_store/disk"

module Sesam
    # sesam's five tables as one JSON document at a path (a store:
    # lib/sesam/store.rb). Every call runs in a
    # transaction that reads the document fresh from disk, under an
    # exclusive flock on the sidecar PATH.lock (the data file is replaced
    # by rename, so it cannot carry the lock), and writes it back only if
    # something changed.
    class JsonStore
        TABLES = %i[users user_keys user_addresses invites passkeys].freeze
        IDS = %i[user_keys invites].freeze

        def initialize(path)
            # Resolved once: a write through a symlink renames over its
            # target, not the link, and every spelling of one file locks
            # the same lock file.
            @path = File.realdirpath(path.to_s)
            @monitor = Monitor.new
            @doc = nil
        end

        def all(table, order: [], **equal)
            rows = transaction { match(table, equal).map(&:dup) }
            rows.sort_by { |row| order.map { sort_key(row[it]) } }
        end

        def first(table, **equal)
            transaction { match(table, equal).first&.dup }
        end

        def count(table, **equal) = transaction { match(table, equal).size }

        def insert(table, row)
            transaction do
                id = next_id(table) if IDS.include?(table)
                stored = row.transform_keys(&:to_sym)
                rows(table) << (id ? stored.merge(id:) : stored)
                id
            end
        end

        def update(table, changes, **equal)
            transaction do
                changes = changes.transform_keys(&:to_sym)
                match(table, equal).each { it.merge!(changes) }.size
            end
        end

        def delete(table, **equal)
            transaction do
                gone = match(table, equal)
                rows(table).reject! { |row| gone.any? { it.equal?(row) } }
                gone.size
            end
        end

        # A transaction inside another joins it: no savepoint, so a
        # rollback undoes the outermost one whole.
        def transaction(&)
            @monitor.synchronize { @doc ? yield : outermost(&) }
        end

        def in_transaction? = @monitor.mon_owned? && !@doc.nil?

        def rollback!
            unless in_transaction?
                raise Error, "rollback! outside a transaction"
            end
            raise Rollback
        end

        private

        def outermost(&)
            flags = File::RDWR | File::CREAT
            File.open("#{@path}.lock", flags, 0o600) do |lock|
                lock.flock(File::LOCK_EX)
                run(&)
            end
        end

        # Kept on every way out but an exception: a block left early
        # (return, break, throw) keeps its writes, as Sequel does; a
        # rollback or an error, none.
        def run
            @doc = Disk.read(@path)
            before = Marshal.load(Marshal.dump(@doc))
            yield
        rescue Rollback
            @doc = nil
        rescue Exception # rubocop:disable Lint/RescueException
            @doc = nil
            raise
        ensure
            settle(before)
        end

        # Out of the transaction before writing: a write that fails must
        # not leave the next call taking itself for a nested one.
        def settle(before)
            doc = @doc
            @doc = nil
            Disk.write(@path, doc) unless doc.nil? || doc == before
        end

        def rows(table)
            unless TABLES.include?(table)
                raise Error, "no such table: #{table.inspect}"
            end
            @doc.fetch(table)
        end

        def match(table, equal)
            rows(table).select { |row| equal.all? { |k, v| row[k] == v } }
        end

        def next_id(table) = @doc[:ids][table] += 1

        # A nil sorts before any value.
        def sort_key(value) = value.nil? ? [0] : [1, value]
    end
end
