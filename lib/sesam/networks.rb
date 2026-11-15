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
            ip = Networks.address(address) or return false
            @list.any? { it.include?(ip) }
        end

        def to_a = @list

        # An IPv4 address a dual-stack socket reports as ::ffff:a.b.c.d,
        # as itself.
        def self.native(ip) = ip.ipv4_mapped? ? ip.native : ip

        # `text` as one address (IPAddr, a mapped IPv4 as its IPv4), or
        # nil: a network is none, since IPAddr would read 10.0.0.0/8 as
        # 10.0.0.0 once written out.
        def self.address(text)
            ip = IPAddr.new(text.to_s)
            native(ip) if one?(ip)
        rescue IPAddr::Error
            nil
        end

        # Whether `ip` is one address, not a wider network.
        def self.one?(ip) = ip.prefix == (ip.ipv4? ? 32 : 128)

        # `text` written as Networks compares it: a mapped IPv4 as its
        # IPv4; anything that is not one address, as given.
        def self.canonical(text) = address(text)&.to_s || text.to_s
    end
end
