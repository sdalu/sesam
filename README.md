# sesam

Who may use a small Rack application, and how they prove it.

## At a glance

The host application requires `sesam/sinatra` for the gate and the
sign-in routes, and `sesam/passkey` beside the core for WebAuthn; both
are optional.

```text
┌──────────────────────────────────────────────┐
│ the host application                         │
│                                              │
│ answer · refuse · parsed_body                │
│ sesam_changed · sesam_notify · sesam_profile │
│ sesam_named · sesam_reached?                 │
└───────────────────────┬──────────────────────┘
                        │
                        ▼
   ┌────────────────────┴───────────────────┐
   │ sesam/sinatra (optional require)       │
   │                                        │
   │ the gate's helpers, the sign-in routes │
   └────────────────────┬───────────────────┘
                        │
                        ▼
       ┌────────────────┴───────────────┐  ┌────────────────────┐
       │ the core                       │  │ sesam/passkey      │
       │                                │  │                    │
       │ Settings · Access · Credential │  │ (optional require) │
       │ Users · Passkeys · Session     │◄─│ WebAuthn           │
       │ Throttle · Spent · Networks    │  └────────────────────┘
       │ Forwarded · Password           │
       └────────────────┬───────────────┘
                        │
                        ▼
     ┌──────────────────┴─────────────────┐
     │ the application's database         │
     │                                    │
     │ users · user_keys · user_addresses │
     │ invites · passkeys                 │
     │ sesam_schema (version)             │
     └────────────────────────────────────┘
```

- [At a glance](#at-a-glance)
- [Passwords](#passwords)
- [Sessions](#sessions)
- [The caller behind proxies](#the-caller-behind-proxies)
- [Counting failures](#counting-failures)
- [Users](#users)
- [Passkeys](#passkeys)
- [Who is calling](#who-is-calling)
- [The routes](#the-routes)
- [Known shortfalls](#known-shortfalls)

- `Sesam::Password`: a password kept as an scrypt hash, its cost and
  salt beside it; checked in constant time; a new one refused when
  shorter than 12 characters or holding control characters
- `Sesam::Session`: a session as a signed cookie holding a name and the
  moment it was given, no secret; a passkey ceremony's challenge carried
  the same way, for five minutes
- `Sesam::Forwarded`: the `for` of each hop of a Forwarded header (RFC
  7239), as an address
- `Sesam::Throttle`: failures counted per key over a window, in memory
- `Sesam::Users`: users by name in a Sequel database: passwords, API
  keys, single-use invitations, the LAN addresses each is known at, the
  moment their sessions were ended
- `Sesam::Passkeys`: each user's passkeys: the public half of a key
  pair, by credential id
- `Sesam::Passkey`: the WebAuthn ceremonies, registering and signing in
  (`require "sesam/passkey"`, with the `webauthn` gem)
- `Sesam::Settings`: what the application tells sesam: its database,
  networks, what it accepts, its Session and Passkey
- `Sesam::Access`: who is calling: a user by key or session, the LAN,
  the application itself, or refused
- `Sesam::Sinatra`: the gate's helpers and the sign-in routes
  (`require "sesam/sinatra"`, with the `sinatra` gem)

Ruby ≥ 3.4; depends on `rack`, `base64` and `sequel`; passkeys also
on `webauthn`, the routes on `sinatra`, which the application adds to
its own Gemfile.

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

Through two trusted proxies, the header grows left to right as each
one forwards; the application walks it from the right:

```text
client  203.0.113.10
  │
  ▼
outer proxy  198.51.100.10
  │
  ▼  Forwarded: for=203.0.113.10
local proxy  192.0.2.10
  │
  ▼  Forwarded: for=203.0.113.10, for=198.51.100.10
application

Forwarded: for=203.0.113.10, for=198.51.100.10
                             └───────────────┘
                                     a proxy: skip
           └──────────────┘
                   not a proxy: the caller

the walk starts at the right and stops here: what the client
itself might have written lands further left, never reached.
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
Sesam::Passkeys.new(db).clear("bob")   # a lost device: every passkey
```

`Sesam.migrate` keeps its own version (`sesam_schema`), apart from
the application's migrations, and refuses a database newer than this
sesam. Its tables are `users` (`name`, `password`, `sessions_since`,
`created_at`), `user_keys`, `invites`, `user_addresses` and
`passkeys`, each made only where missing. Anything else the
application knows of a person (names, an email address) goes in a
table of its own keyed by `user`, a foreign key to `users` cascading
on delete, migrated after sesam's. A passkey's `public_key` is text
where a String would be `varchar(255)` (MySQL), an RSA key being
longer; SQLite's table is left as it is. Every moment (`created_at`,
`sessions_since`, an invitation's `expires_at` and `used_at`) is an
integer, milliseconds since the epoch, read the same whatever Sequel
timezone a process sets; sesam's objects give it back as a `Time`,
and its answers as ISO 8601 (`2026-11-17T13:50:46.640+01:00`).
Migrating a database whose moments were times reads each as the
migrating process does: run it with the Sequel timezone they were
written with, and on SQLite 3.35 or later.

A name is refused when a user's differs from it by case alone, and a
`reserved` one (strings or symbols) whatever its case.

An invitation lasts a week unless told, and the newest withdraws
those still open. `redeem` runs its block in the same transaction:
what the block refuses leaves the invitation open. A wrong password
and an unknown name take the same time, the name checked against a
decoy hash.

## Passkeys

```ruby
require "sesam/passkey"   # needs the webauthn gem

passkey = Sesam::Passkey.new("https://app.example.org",
                             name: "App", handle: "app/")
keys = Sesam::Passkeys.new(db)

options = passkey.registration_for("alice", keys)  # to the browser
# ... navigator.credentials.create answers `credential`
passkey.register!("alice", credential, options.challenge, keys,
                  label: "phone")

options = passkey.authentication                     # no name asked
# ... navigator.credentials.get answers `credential`
passkey.authenticate!(credential, options.challenge, keys)  # => "alice"
```

The ceremony, in two calls:

```text
┌─────────┐               ┌───────────────┐   ┌─────────────┐
│ Browser │               │ Authenticator │   │ Application │
└────┬────┘               └───────┬───────┘   └──────┬──────┘
     │                            │                  │
     │  POST /session/challenge   │                  │
     │──────────────────────────────────────────────►│
     │                            │                  │
     │                            │ options + cookie │
     │◄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄│
     │                            │                  │
     │      credentials.get       │                  │
     │───────────────────────────►│                  │
     │                            │                  │
     │       the assertion        │                  │
     │◄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄│                  │
     │                            │                  │
     │ POST /session {credential} │                  │
     │──────────────────────────────────────────────►│
     │                            │                  │
     │                            │                  │──┐
     │                            │                  │  │ checked, spent
     │                            │                  │◄─┘
     │                            │                  │
     │                            │    cookie set    │
     │◄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄│
     │                            │                  │
```

The origin is what the browser's address bar shows: `https://HOST`
with an optional port, or `http://localhost`; anything else is
refused (`Sesam::Passkey::Error`). `name` is what the browser shows
when it asks for a finger; each user's handle is derived from
`handle` and their name, so changing it makes every device register
a second credential. The challenge between the two calls of a
ceremony is the caller's to carry (Session#challenge_cookie).
`authenticate!` answers nil for a signature, challenge, origin or
credential that is not right, and `register!` raises `WebAuthn::Error`.

## Who is calling

```ruby
SESAM = Sesam::Settings.new(
    database: ->(&block) { block.call(db) },  # yields a Sequel database
    lan: ["192.0.2.0/24"], proxies: ["127.0.0.1"],
    accept: %w[key passkey password], mount: "/app",
    session:, passkey:, reserved: %w[root], app: "app"
)
found = SESAM.access.caller_for(env)
found.verdict  # :credential, :lan or :refused
found.name     # "alice", "lan:192.0.2.9", "app:warm"
```

The order `Access#caller_for` decides in:

```text
┌──────────────────────────────────┐
│ a Bearer key (key accepted) or a │
│ session cookie naming a user     │──► admitted as that user
└─────────────────┬────────────────┘
                  │ else
                  ▼
┌──────────────────────────────────┐
│ a LAN address that is no proxy   │──► admitted as lan:ADDR, or as
└─────────────────┬────────────────┘   the user known at that address
                  │ else
                  ▼
┌──────────────────────────────────┐
│ the env key APP.internal         │──► admitted as APP:NAME
└─────────────────┬────────────────┘
                  │ else
                  ▼
┌───────────────┐
│ refused (401) │
└───────────────┘
```

Two settings say what an account's recovery does. `reset_passkeys`:
what a reset by invitation does to the passkeys a user had, `keep`
(the default: kept, their other sessions ended), `drop` (both gone:
a lost device signs in no more), or `drop_keep_sessions` (the
passkeys alone). `recovery`: whether a link may be asked for from the
sign-in screen (`POST /session/recover`, false by default), the link
lasting `recovery_for` seconds (an hour).

A setting not in `Settings::DEFAULTS` is refused, as are networks that
do not parse, a passkey without a session, and `accept` empty or
naming anything but `key`, `passkey` and `password`. A passkey given
while passkeys are not accepted is dropped. The caller is, in order:
the user a Bearer key or a session names (a key only where `key` is
accepted, a query string never); a LAN caller, named for the user
known at that address if any (a name, not a proof); a request carrying
`app.internal` in its env, which no HTTP request can set; else
refused. Behind `proxies` the caller is the rightmost Forwarded hop
that is no proxy; X-Forwarded-For is never read. An IPv4 address a
dual-stack socket reports as `::ffff:a.b.c.d` is that IPv4 address,
for the networks and the throttle alike. The Bearer scheme is read
whatever its case.

## The routes

```ruby
require "sesam/sinatra"

class App < Sinatra::Base
    register Sesam::Sinatra
    set :sesam, SESAM
    before do
        same_site!
        admit! unless sesam_open?
    end
    get("/secret") { answer({ who: }) }
end
```

`same_site!` refuses (403) a write the browser says comes from another
site (`Sec-Fetch-Site: cross-site`, which no page can set), on every
route, open or not: a page elsewhere must not drive a LAN browser into
acting, nor sign it in as someone else. A program sends no such header
and passes. `admit!` refuses an unknown caller with a 401, `WWW-Authenticate:
Bearer realm="app"` and `X-App-Sign-In` listing the browser's ways in
(`password passkey`, empty for none, with `recover` where a link may
be asked for); `who` is the caller's name.

- `GET /session`: who is calling: name, via, the profile, password set,
  the passkeys' origin, the ways in
- `POST /session/password` (open): signs in by name and password
- `PUT /session/password`: changes one's password, the current one
  given; other sessions end
- `DELETE /session` (open): signs out
- `POST /session/challenge`, `POST /session` (open): signs in by
  passkey, two calls
- `GET /passkeys`, `POST /passkeys/challenge`, `POST /passkeys`,
  `DELETE /passkeys/:id`: one's passkeys
- `POST /session/invite/check` (open): whose invitation a token is,
  without spending it
- `POST /session/invite` (open): spends it on a password; other sessions
  end
- `POST /session/invite/challenge`, `POST /session/invite/passkey`
  (open): spends it on a passkey
- `POST /session/recover` (open): a link asked for by `who`, a login or
  what the application knows a user by; 202 whatever it names; 404 where
  `recovery` is off

An invitation's life:

```text
         ┌──────────────────────────────────────────┐
         │ an invitation made                       │
         │ (Users#invite, or POST /session/recover) │
         └─────────────────────┬────────────────────┘
                               │
                               ▼
              ┌────────────────┴────────────────┐
              │ the link, its token after the # │
              └────────────────┬────────────────┘
                               │
                               ▼
                ┌──────────────┴─────────────┐
                │ POST /session/invite/check │
                │ (read, not spent)          │
                └──────────────┬─────────────┘
                               │
            ┌──────────────────┴─────────────┐
            ▼                                ▼
┌───────────┴──────────┐    ┌────────────────┴────────────────┐
│ POST /session/invite │    │ /session/invite/challenge, then │
│                      │    │ /session/invite/passkey         │
│ spent on a password  │    │ spent on a passkey              │
└───────────┬──────────┘    └────────────────┬────────────────┘
            │                                │
            └──────────────────┬─────────────┴──► refused: leaves it open
                               │
                               ▼
         ┌─────────────────────┴────────────────────┐
         │ their other sessions end, their passkeys │
         │ go, each as reset_passkeys says          │
         └─────────────────────┬────────────────────┘
                               │
                               ▼
           ┌───────────────────┴──────────────────┐
           │ the user signs in with what they set │
           └──────────────────────────────────────┘
```

A ceremony's challenge is spent once, remembered as spent until it
would have lapsed, so an answer sent again with its cookie is refused.
A credential id is one user's: a registration offering another user's
is refused (422), theirs kept. Whatever refuses an invitation's
password or passkey leaves the invitation open.

A link asked for (`POST /session/recover`) is answered the same
whether or not it names anyone, and at once: the link is handed over
after the answer, on a thread of its own, since a mail sent only for
someone who exists would otherwise show in the time it takes. It is
made only for a user the application can reach (`sesam_reached?`), so
that an open invitation of someone else's is never withdrawn in vain;
an address asks 20 times a window (429 after), a name is mailed 3
times a window (silently after).

Bodies are JSON (`name`, `password`, `current`, `token`, `credential`,
`label`). Failed sign-ins are counted by name and address (5) and by
address (20), failed invitation lookups by address (20), over the
Throttle's window: past them, 429. A way not accepted answers 404 on
its routes.

What the application may define, as helper modules, before or after
registering sesam; sesam's own fills only what is missing:

- `answer(data)`: every answer; by default `{"data": …}`.
- `refuse(status, message, field = nil)`: every refusal; by default
  raises `Sesam::Sinatra::Refused`, answered `{"error", "field"}`; an
  application's own must raise too, never `halt`, or a refusal inside a
  transaction commits it.
- `parsed_body`: reading a body; by default the JSON object; 415 for a
  body not said `application/json`, 422 for one that is no object.
- `sesam_changed(name, db)`: in the transaction where a user's way in
  changed; by default nothing.
- `sesam_notify(name, kind)`: after it, `:password` or `:passkey`; by
  default nothing.
- `sesam_profile(name)`: merged into `GET /session` and the invitation
  check; by default `{}`. A key of sesam's own there (`name`, `via`,
  `password`…) raises `Sesam::Error` rather than replace it.
- `sesam_named(text)`: a link asked for: the user `text` names besides a
  login (an email address); by default `nil`.
- `sesam_reached?(name, token)`: a link asked for: hand the invitation
  over (mail it); false keeps none; by default `false`.
- `sesam_asked(name, db)`: a link handed to `name`, in the invitation's
  transaction in `db`; by default nothing.

These two run after the answer, on a thread of their own: a
thread-local the application set for the request (who acts, for an
audit) is not there, so they take what they need from the request
itself. A failure there is said on the server's output.

## Known shortfalls
- A link asked for is mailed inside its invitation's transaction (kept
  only if it reached its user), so on SQLite other writers wait for the
  mail, and fail past the busy timeout (Sequel's 5 s by default).
- On MySQL, a passkey's credential id is `varchar(255)`, which an
  authenticator making longer ids would not fit.
