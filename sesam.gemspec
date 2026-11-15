# frozen_string_literal: true

require_relative "lib/sesam/version"

Gem::Specification.new do |s|
    s.name        = "sesam"
    s.version     = Sesam::VERSION
    s.authors     = ["Stéphane D'Alu"]
    s.email       = ["sdalu@sdalu.com"]

    s.summary     = "Sign-in for a small Rack application"
    s.description = "Who may use a small Rack application and how they " \
                    "prove it: passwords kept as scrypt hashes, sessions " \
                    "as signed cookies holding no secret, the caller " \
                    "behind trusted proxies read from the Forwarded " \
                    "header, and failures counted over a window."
    s.homepage    = "https://github.com/sdalu/sesam"
    s.license     = "MIT"

    s.required_ruby_version = ">= 3.4"

    s.metadata = {
        "homepage_uri" => s.homepage,
        "rubygems_mfa_required" => "true"
    }

    s.files = Dir.chdir(__dir__) do
        Dir["{lib}/**/*", "LICENSE.txt", "README.md"]
            .reject { |f| File.directory?(f) }
    end

    s.require_paths = ["lib"]

    # base64 left Ruby's default gems in 3.4: Password and Session encode
    # with it.
    s.add_dependency "base64", "~> 0.2"
    # Users and Passkeys are kept in the application's database.
    s.add_dependency "sequel", "~> 5.100"
    # Session reads the request's cookies through Rack::Request.
    s.add_dependency "rack", ">= 3.0"
end
