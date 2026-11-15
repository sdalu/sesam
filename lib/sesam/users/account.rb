# frozen_string_literal: true

require "ipaddr"

module Sesam
    class Users
        # What a user is besides a name and a way in (Users): the LAN
        # addresses they are known at, and the moment their sessions were
        # ended, before which none counts.
        module Account
            # A LAN address `name` is known at: a caller from it on a
            # trusted network is named for them (a name, not a proof). Not
            # loopback, which is every caller through a socket or a
            # proxy on this machine.
            def address!(name, address, now: Time.now)
                found!(name)
                ip = ip_of(address)
                if ip.loopback?
                    raise Error, "#{ip} is every caller through a socket " \
                                 "or a proxy here: not one person's"
                end
                @db[:user_addresses].where(address: ip.to_s).delete
                @db[:user_addresses].insert(address: ip.to_s, user: name,
                                            created_at: now)
            end

            def unaddress!(name, address)
                gone = @db[:user_addresses]
                       .where(user: name.to_s, address: ip_of(address).to_s)
                       .delete
                raise Error, "#{name} is not known at #{address}" if gone.zero?
            end

            def addresses_of(name)
                @db[:user_addresses].where(user: name.to_s).order(:address)
                                    .select_map(:address)
            end

            # Whose LAN address `peer` is, or nil.
            def address_owner(peer)
                @db[:user_addresses].where(address: ip_of(peer).to_s).get(:user)
            rescue Error
                nil
            end

            # Every session `name` holds, ended: those given before now no
            # longer count (a password set or reset, a sign-out everywhere).
            def end_sessions!(name, now: Time.now)
                found!(name)
                users.where(name:).update(sessions_since: now)
            end

            # Whether a session given to `name` at `issued` (milliseconds)
            # counts: given after their sessions were last ended, or after
            # they were added (a name removed and added again holds none of
            # the old ones).
            def session_valid?(name, issued)
                row = users.where(name: name.to_s).first
                return false unless row
                since = row[:sessions_since]
                issued >= (since.to_r * 1000).floor
            end

            private

            def ip_of(address)
                IPAddr.new(address.to_s).tap do |ip|
                    raise Error, "one address, not a network: #{address}" if
                        ip.prefix != (ip.ipv4? ? 32 : 128)
                end
            rescue IPAddr::Error
                raise Error, "not an IP address: #{address.inspect}"
            end
        end
    end
end
