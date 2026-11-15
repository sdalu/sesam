# sesam

Who may use a small Rack application, and how they prove it.

| Piece             | What it does                                             |
|-------------------|----------------------------------------------------------|
| `Sesam::Password` | a password kept as an scrypt hash, its cost and salt beside it; checked in constant time; a new one refused when shorter than 12 characters or holding control characters |
| `Sesam::Session`  | a session as a signed cookie holding a name and the moment it was given, no secret; a passkey ceremony's challenge carried the same way, for five minutes |
| `Sesam::Forwarded`| the `for` of each hop of a Forwarded header (RFC 7239), as an address |
| `Sesam::Throttle` | failures counted per key over a window, in memory          |
| `Sesam::Users`    | users by name in a Sequel database: passwords, API keys, single-use invitations, the LAN addresses each is known at, the moment their sessions were ended |
| `Sesam::Passkeys` | each user's passkeys: the public half of a key pair, by credential id |

Ruby ≥ 3.4; depends on `rack`, `base64` and `sequel`.

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

## Users

```ruby
db = Sequel.sqlite("app.db")
Sesam.migrate(db)            # sesam's tables, before the application's
users = Sesam::Users.new(db, reserved: %w[root])

users.add("alice")
token = users.invite("alice")          # shown once; its digest kept
users.redeem(token) { users.password!(it, "a long enough password") }
users.password_match?("alice", "a long enough password")  # => true
key = users.key("alice", label: "script")                 # shown once
users.key_owner(key)                                      # => "alice"
users.address!("alice", "192.0.2.7")   # a LAN caller named, not proved
users.end_sessions!("alice")           # sessions given before end
users.session_valid?("alice", held.issued)
users.remove("alice")                  # their ways in go with them
```

`Sesam.migrate` keeps its own version (`sesam_schema`), apart from
the application's migrations, and refuses a database newer than this
sesam. Its tables are `users` (`name`, `password`, `sessions_since`,
`created_at`), `user_keys`, `invites`, `user_addresses` and
`passkeys`, each made only where missing. Anything else the
application knows of a person (names, an email address) goes in a
table of its own keyed by `user`, a foreign key to `users` cascading
on delete, migrated after sesam's.

An invitation lasts a week unless told, and the newest withdraws
those still open. `redeem` runs its block in the same transaction:
what the block refuses leaves the invitation open. A wrong password
and an unknown name take the same time, the name checked against a
decoy hash.

## Known shortfalls

- Passkey ceremonies (WebAuthn) are not here yet, nor the Sinatra
  layer that admits callers and serves the sign-in routes: both are
  ClimatControl's still.
- No release yet: `Sesam::VERSION` is 0.0.0.
