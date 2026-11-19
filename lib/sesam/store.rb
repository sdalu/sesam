# frozen_string_literal: true

module Sesam
    # A store holds sesam's five tables (users, user_keys,
    # user_addresses, invites, passkeys) as rows, Hashes with Symbol
    # keys; a column not set reads as nil. Two answer to it alike:
    # SequelStore (the application's database) and JsonStore (a file).
    #
    # `equal` is column => value, matched by equality, a nil matching a
    # column not set; anything else is filtered by the caller.
    #
    # - all(table, order: [], **equal): the rows, sorted by the columns
    #   of `order`, a nil first
    # - first(table, **equal), count(table, **equal)
    # - insert(table, row): the id the store gives a row of user_keys or
    #   invites (never given twice), nil for the other tables
    # - update(table, changes, **equal), delete(table, **equal): the
    #   rows changed or removed
    # - transaction { }: the block's value, its changes kept together or
    #   not at all (kept when the block is left early, by return, break
    #   or throw; none on an exception); one opened inside another joins
    #   it
    # - rollback!: the outermost transaction keeps nothing and answers
    #   nil; an Error outside one
    # - in_transaction?
    #
    # A table not among the five is an Error. A store holds no keys and
    # does not cascade: Users and Passkeys check a name free or a user
    # there in the transaction that writes, and Users#remove takes what
    # was a user's itself.
    #
    # Raised by rollback!. Not an Error, as nothing failed.
    class Rollback < StandardError; end
end
