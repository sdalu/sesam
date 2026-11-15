# sesam

Who may use a small Rack application, and how they prove it. The
pieces that need nothing but the standard library and Rack:

| Piece             | What it does                                             |
|-------------------|----------------------------------------------------------|
| `Sesam::Password` | a password kept as an scrypt hash, its cost and salt beside it; checked in constant time; a new one refused when shorter than 12 characters or holding control characters |
| `Sesam::Session`  | a session as a signed cookie holding a name and the moment it was given, no secret; a passkey ceremony's challenge carried the same way, for five minutes |
| `Sesam::Forwarded`| the `for` of each hop of a Forwarded header (RFC 7239), as an address |
| `Sesam::Throttle` | failures counted per key over a window, in memory          |

Ruby ≥ 3.4; depends on `rack` and `base64`.

```ruby
# Gemfile
gem "sesam", github: "sdalu/sesam"
```

## Passwords

```ruby
require "sesam"

kept = Sesam::Password.digest("a long enough password")
# => "scrypt$16384$8$1$SALT$HASH"
Sesam::Password.match?("a long enough password", kept)  # => true
Sesam::Password.refusal("short")
# => "a password is 12 characters at least"
```

`match?` reads the cost from the hash, so a hash made at another cost
still checks. Anything not an scrypt hash matches nothing.

## Sessions

```ruby
session = Sesam::Session.new(secret, lifetime: 30 * 86_400,
                             cookie: "app_session",
                             ceremony: "app_ceremony")
attributes = session.cookie_for("alice", "/app")
# set it as the response's `app_session` cookie (Rack's set_cookie)
session.held_from(env)  # => Held(name: "alice", issued: MILLISECONDS)
session.forget("/app")  # the attributes that drop it
```

The secret (32 bytes or more of randomness; nothing here checks it)
must outlive the process.
A cookie is Secure, HttpOnly, SameSite=Lax, its path the mount given.
A forged, tampered or expired cookie reads as nil. Nothing on the
server holds a session: its holder decides whether the name still
counts, `issued` against the moment that user's sessions were last
ended. The cookies' names default to `sesam_session` and
`sesam_ceremony`; changing one signs everybody out.

## The caller behind proxies

```ruby
Sesam::Forwarded.fors('for=192.0.2.60, for="[2001:db8::17]:4711"')
# => ["192.0.2.60", "2001:db8::17"]
```

A hop naming no address (`unknown`, an obfuscated name) or none is
`""`. Which hop to believe is the caller's: the rightmost not a proxy
it trusts.

## Counting failures

```ruby
throttle = Sesam::Throttle.new(window: 900)
throttle.failed!("try:alice@192.0.2.7")
throttle.blocked?("try:alice@192.0.2.7", 5)  # => false until 5
throttle.clear!("try:alice@192.0.2.7")
```

## Known shortfalls

- Users, API keys, invitations and passkeys are not here yet: they are
  ClimatControl's still, as is the Sinatra layer that admits callers
  and serves the sign-in routes.
- No release yet: `Sesam::VERSION` is 0.0.0.
