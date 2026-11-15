# frozen_string_literal: true

module Sesam
    # The Forwarded request header (RFC 7239): each proxy's hop, left
    # to right, its `for` the caller it saw. X-Forwarded-For is another
    # header, read by nothing here.
    module Forwarded
        module_function

        # The `for` of each hop, as an address: quotes, an IPv6's
        # brackets and a port taken off. A hop without one, or naming
        # no address ("unknown", an obfuscated name), is "": it stops
        # a walk and admits nothing.
        def fors(header)
            header.to_s.split(",").map do |hop|
                pair = hop.split(";").map(&:strip)
                          .find { it.downcase.start_with?("for=") }
                pair ? node(pair.split("=", 2).last) : ""
            end
        end

        # "1.2.3.4", "\"1.2.3.4:80\"", "\"[2001:db8::1]:4711\"" => the
        # address.
        def node(value)
            text = value.delete('"').strip
            return text[/\A\[([^\]]+)\]/, 1].to_s if text.start_with?("[")
            text.count(":") == 1 ? text.split(":").first : text
        end
    end
end
