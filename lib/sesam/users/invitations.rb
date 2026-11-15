# frozen_string_literal: true

require "openssl"
require "securerandom"

module Sesam
    class Users
        # Invitations (Users): a single-use token, only its digest kept,
        # lasting a week unless told, the newest withdrawing those still
        # open. Spent (#redeem), it signs its user in, and what is set
        # with it (a password) is kept only with it spent.
        module Invitations
            # How long an invitation lasts unless told.
            INVITE_FOR = 7 * 86_400

            Invite = Data.define(:id, :user, :created_at, :expires_at,
                                 :used_at)

            # A new invitation for `name`, lasting `seconds`; the ones still
            # open withdrawn, so that only the newest link works. The token,
            # shown once: given to the block too, in the transaction, so
            # that what fails there (a mail) leaves nothing issued.
            def invite(name, seconds: INVITE_FOR, now: Time.now)
                found!(name)
                token = SecureRandom.urlsafe_base64(32)
                @db.transaction do
                    open_invites(name, now).update(used_at: now)
                    invites.insert(user: name, digest: digest(token),
                                   created_at: now, expires_at: now + seconds)
                    yield token if block_given?
                end
                token
            end

            # The open invitation `token` is, or nil: unknown, used and
            # lapsed alike.
            def invitation(token, now: Time.now)
                return nil if token.to_s.empty?
                row = invites.where(digest: digest(token), used_at: nil)
                             .where { expires_at > now }.first
                row && Invite.new(**row.slice(*Invite.members))
            end

            # Spends `token`, once: the block, given its user, runs in the
            # same transaction, so what it sets (a password) is kept only
            # with the invitation used, and an invitation used only with it.
            # The user, or nil for a token not open; two redeeming at once,
            # one wins.
            def redeem(token, now: Time.now)
                @db.transaction do
                    invite = invitation(token, now:)
                    next nil unless invite
                    spent = invites.where(id: invite.id, used_at: nil)
                                   .update(used_at: now)
                    next nil unless spent == 1
                    yield invite.user if block_given?
                    invite.user
                end
            end

            private

            def open_invites(name, now)
                invites.where(user: name, used_at: nil)
                       .where { expires_at > now }
            end

            def invites = @db[:invites]
        end
    end
end
