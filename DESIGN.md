# Design

## Pieces that hold no state but what they are given

Each piece takes what it works on as arguments and keeps nothing
between calls but its configuration (Throttle's count aside): no
database, no global settings, no framework. An application wires
them; a test builds them with a line.

## Passwords: scrypt from OpenSSL

`OpenSSL::KDF.scrypt` is in the standard library, so no native gem
(bcrypt, argon2) is needed. The cost (N=2^14, r=8, p=1: 16 MiB and
some tens of milliseconds) is written in the hash beside the salt, so
a later cost still checks an older hash. An unknown name is to be
checked against a decoy hash by the caller, so that both take the same
time; `match?` answers false for anything it cannot read rather than
raising.

## Sessions: signed, not stored

A session is a name and the moment it was given, signed with HMAC-
SHA256 and an expiry: no table to sweep, nothing to look up per
request. Not the API key in a cookie: a stolen session is a session,
while a stolen key would also be every program's bearer token. The
price is revocation: nothing on the server holds a session, so a
user's sessions end by a moment kept with the user (`issued` must be
later), checked by whoever reads the session.

Its anatomy, for a made-up `alice` and made-up numbers:

```text
YWxpY2U6MTAwMCA1MDAw.oyIuymvmKiRvuGTCNa6cc1JmzclDsjTkBQzhLuHqvmU
└──────────────────┘─└─────────────────────────────────────────┘
base64url('NAME:ISSUED_MS EXPIRY_S')
                       base64url(HMAC-SHA256(secret, payload))

the challenge cookie: the same, the challenge in place of NAME:ISSUED_MS
```

A passkey ceremony is two requests, and the challenge must reach the
second before any session exists: it rides in a cookie signed the same
way, for five minutes. A challenge nobody can forge is as safe held
by the client, but not spent by it: dropping the cookie spends it
for an honest browser only, so the server also remembers each
challenge spent (Spent, in memory as Throttle) until it would have
lapsed. A synced passkey's counter stays at 0 and cannot tell a
replay.

The format is ClimatControl's, byte for byte (test/session_test.rb
pins it), so that its sessions survive the move; the cookies' names
are parameters for the same reason.

## Tables of its own, migrated apart

sesam's tables carry what signing in needs and nothing an application
might add: a person's names or address are the application's, in a
table keyed by the user. Two migrators altering one table would leave
neither owning it, so sesam keeps its own version table and runs
first, and its first migration makes each table only where missing,
for a database that held them before sesam. A database past what this
sesam knows is refused, not migrated down.

A user's name is theirs whatever its case: a name differing from
another by case alone is refused, as reserved names are compared,
since nobody reading an audit tells them apart, and a database
comparing without case would take one for the other.

Keys and invitations are 256 random bits, kept as SHA-256 digests: a
fast digest loses nothing against that much entropy, and a lookup by
digest tells a guesser nothing a guess would not. Names an
application keeps for itself (an audit's `root`) are given, not
built in.

## Passkeys: an optional require

`sesam/passkey` is loaded on its own, and `webauthn` (with its CBOR
and COSE gems) is not in the gemspec: an application signing in by
password alone pulls none of it in. Missing, the require says which
gem to add rather than failing deeper.

The origin is configured, never read from a request: WebAuthn binds a
credential to the origin the browser sees, and behind a proxy the
request says what the proxy wrote. Signing in names no credential
(no allow-list), since listing the accepted credentials would tell
anybody which users exist; the credential's id says whose it is, and
only one registered here counts, whatever its signature proves.

## The gate in the core, the routes in Sinatra

Who is calling (Access, Credential, Accept, Settings) needs a Rack env
and nothing more, so it is in the core, for any Rack application; the
routes need a framework, and are a Sinatra extension, loaded on its
own like passkeys. One Settings object carries everything the gate
and the routes read, built once; an unknown key in it is refused
rather than ignored, a typo being a setting silently left at its
default.

sesam reaches users through a callable yielding a Sequel database:
the application decides how it opens and locks its database, and
sesam builds Users and Passkeys on what it is given, with the
reserved names. The application's part of a change (an audit row)
needs the request, so it is a helper (`sesam_changed`), not a
callable in the settings, and it runs inside the change's transaction
so that one is kept only with the other.

An application's helpers are its own: sesam fills only the ones it
lacks, whichever is registered first, so an API with its own
envelope (`answer`, `refuse`) keeps it on sesam's routes. The route
paths are fixed: a front and a schema describe them, and a prefix is
where the application mounts its API.

The application's name (`app`) names what a client sees of it: the
realm of a 401, the header listing the ways in, the env key of its
own requests; the cookies' names are the Session's.

## A refusal raises, and a write states its origin

A refusal is an exception (`Refused`), not Sinatra's `halt`: a halt is
a throw, and Sequel commits a transaction a throw leaves, so an
invitation spent inside one would stay spent behind a 422. An
application's own `refuse` must raise as well.

A browser posts `text/plain` to any site without asking, and can make
it a JSON text: so a body is JSON only when it says so (415 else), the
kind a foreign page can send only after a preflight it does not pass;
and a write a browser marks `Sec-Fetch-Site: cross-site` is refused
before anything else. The header is the browser's, not the page's, and
needs no list of the application's own names, which behind proxies the
request itself cannot give.

## Recovery: an invitation, asked for or given

A forgotten password or a lost device is answered by an invitation,
as a first sign-in is; nothing else signs anyone in. By default only
the application gives one (sesam has no mail): asking from the
sign-in screen (`recovery`) is off, since a route that takes a name or
an address is one more door, and answering it differently for a name
that exists would tell who does. It answers the same in every case,
in the same time too: the link is handed over after the answer, on a
thread, since mailing it takes long and happens only for a user who
exists, and the hooks it calls then run off the request's thread. It
makes an invitation only for a user the application can reach (an
invitation withdraws the one still open, which asking for nobody must
not do), and is counted by address and, silently, by name.

A reset ends the user's other sessions; whether it also drops the
passkeys they had is the application's call (`reset_passkeys`): kept,
a lost phone still signs in after its owner's reset; dropped, every
device they still hold must register again.

## Forwarded, not X-Forwarded-For

RFC 7239's header names each hop; a client can write only to the left
of what trusted proxies append, so the caller is the rightmost hop not
a trusted proxy. X-Forwarded-For is not read: an application behind a
proxy writing only that one must have the proxy write Forwarded.

## Throttling: never by name alone

Counting failures by name alone would let anyone knowing a name lock
its owner out from anywhere; the keys are the caller's to build (a
name with an address, an address). In memory: for an application in
one process, a restart costs a guesser one window. Only keys with
failures in the window are kept, so a flood of lookups costs nothing.
