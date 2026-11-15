# frozen_string_literal: true

require "ipaddr"

module Sesam
    # A list of networks (192.0.2.0/24, ::1/128, one address), and
    # whether an address is in one of them: false for anything that is
    # not one address.
    class Networks
        # A network that does not parse.
        class Error < Sesam::Error; end

        # `given` as Networks: kept when it is one already.
        def self.of(given, name)
            given.is_a?(Networks) ? given : new(given, name)
        end

        # name: what the list is called, in a refusal.
        def initialize(given, name = "networks")
            @list = Array(given).map do |net|
                net.is_a?(IPAddr) ? net : IPAddr.new(net.to_s)
            end.freeze
            freeze
        rescue IPAddr::Error
            raise Error, "#{name}: networks, as 192.0.2.0/24 or ::1/128"
        end

        def include?(address)
            ip = Networks.native(IPAddr.new(address.to_s))
            @list.any? { it.include?(ip) }
        rescue IPAddr::Error
            false
        end

        def to_a = @list

        # An IPv4 address a dual-stack socket reports as ::ffff:a.b.c.d,
        # as itself.
        def self.native(ip) = ip.ipv4_mapped? ? ip.native : ip

        # `address` written as Networks compares it: a mapped IPv4 as its
        # IPv4; anything that is no address, as given.
        def self.canonical(address)
            native(IPAddr.new(address.to_s)).to_s
        rescue IPAddr::Error
            address.to_s
        end
    end
end
