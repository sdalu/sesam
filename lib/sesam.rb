# frozen_string_literal: true

require "sesam/version"
require "sesam/password"
require "sesam/session"
require "sesam/forwarded"
require "sesam/throttle"

# Who may use a small Rack application, and how they prove it
# (README.md): passwords kept as scrypt hashes, sessions as signed
# cookies, the caller behind trusted proxies read from Forwarded, and
# failures counted over a window.
module Sesam
end
