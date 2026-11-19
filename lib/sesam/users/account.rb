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
                ip = person_ip(address)
                @store.transaction do
                    name = found!(name)
                    @store.delete(:user_addresses, address: ip.to_s)
                    @store.insert(:user_addresses,
                                  { address: ip.to_s, user: name,
                                    created_at: Stamp.ms(now) })
                end
            end

            def unaddress!(name, address)
                gone = @store.delete(:user_addresses,
                                     user: name.to_s,
                                     address: ip_of(address).to_s)
                raise Error, "#{name} is not known at #{address}" if gone.zero?
            end

            def addresses_of(name)
                @store.all(:user_addresses, order: [:address], user: name.to_s)
                      .map { it[:address] }
            end

            # Whose LAN address `peer` is, or nil.
            def address_owner(peer)
                get(:user_addresses, :user, address: ip_of(peer).to_s)
            rescue Error
                nil
            end

            # Every session `name` holds, ended: those given before now no
            # longer count (a password set or reset, a sign-out everywhere).
            def end_sessions!(name, now: Time.now)
                name = found!(name)
                @store.update(:users, { sessions_since: Stamp.ms(now) }, name:)
            end

            # Whether a session given to `name` at `issued` (milliseconds)
            # counts: given after their sessions were last ended, or after
            # they were added (a name removed and added again holds none of
            # the old ones).
            def session_valid?(name, issued)
                row = @store.first(:users, name: name.to_s)
                return false unless row
                issued >= row[:sessions_since].to_i
            end

            private

            # `address` as one person's: Error for loopback, which is
            # every caller through a socket or a proxy here.
            def person_ip(address)
                ip_of(address).tap do |ip|
                    next unless ip.loopback?
                    raise Error, "#{ip} is every caller through a socket " \
                                 "or a proxy here: not one person's"
                end
            end

            def ip_of(address)
                IPAddr.new(address.to_s).tap do |ip|
                    raise Error, "one address, not a network: #{address}" unless
                        Networks.one?(ip)
                end
            rescue IPAddr::Error
                raise Error, "not an IP address: #{address.inspect}"
            end
        end
    end
end
