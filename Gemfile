# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
    gem "minitest", "~> 5.25"
    gem "rake", "~> 13.2"
    gem "rubocop", "~> 1.90"
    # The database the tests keep users in, in memory.
    gem "sqlite3", "~> 2.0"
    # sesam/passkey's relying party, and its fake authenticator.
    gem "webauthn", "~> 3.4"
    # sesam/sinatra's routes, driven as a browser would.
    gem "rack-test", "~> 2.3"
    gem "sinatra", "~> 4.2"
end
