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
sesam knows is refused, not migrated down. A later migration changes
only what a database needs: a passkey's public key made text where a
String has a length (MySQL), SQLite left as it is, since copying a
table anew to change a length it ignores is a risk for nothing.

Every moment sesam keeps is an integer, milliseconds since the epoch,
never a time column. A time column reads through the Sequel timezone
of the process reading it, a setting that belongs to the host and
that a console or a script may lack: rows written as UTC and read as
local time shift by the offset, and an ended session counts for an
hour more. An integer reads the same everywhere. Milliseconds, not
seconds, because sessions are stamped to the millisecond: in seconds,
a session given earlier in the very second its user's sessions were
ended would still count. The migration that made them integers reads
each old time as the migrating process reads it, so it is right only
where the host migrates with the setting its rows were written with;
nothing in a naive time says which that was. Answers give a moment as
ISO 8601 to the millisecond, its offset said.

A user's name is theirs whatever its case: a name differing from
another by case alone is refused, as reserved names are compared,
since nobody reading an audit tells them apart, and a database
comparing without case would take one for the other.

Keys and invitations are 256 random bits, kept as SHA-256 digests: a
fast digest loses nothing against that much entropy, and a lookup by
digest tells a guesser nothing a guess would not. Names an
application keeps for itself (an audit's `root`) are given, not
built in.

## Two stores, one set of calls

A tool for one household need not run a database to sign its users
in, so the tables sit behind a store: the application's Sequel
database (SequelStore) or a JSON file of their own (JsonStore), both
answering the calls of lib/sesam/store.rb, and the suite runs once on
each. The calls match by equality alone, anything else (a name's
case, an invitation's expiry) filtered in Ruby: the tables hold a
household's rows, and a richer query language is a second database
engine to keep honest. A transaction inside another joins it, as
Sequel's do, and a rollback undoes the whole: a change is kept whole
or not at all, and savepoints would let half of one stand. A block
left early (return, break, throw) keeps its writes on both, as
Sequel's does: one rule for both stores, the refusals raising. A store
holds no keys and does not cascade: Users and Passkeys check that a
name is free, or that a user exists, in the transaction that writes,
where one process at a time runs, and Users removes what was a
user's itself, the same on either.

JsonStore is one document rewritten whole, not a log appended to: at a
household's size the rewrite costs nothing, while a log needs
tombstones for what is deleted (a spent invitation, a passkey gone)
and a compaction to bound it. Not JSON with comments either: sesam
writes the file whenever a passkey's counter moves at sign-in, and a
comment would be gone at the first. The lock is a file beside it,
since the document is replaced by rename and a lock on it would stay
with the old one; each transaction reads the document afresh under it,
as another process may have written. The file holds password hashes
and key digests, so it is made readable by its owner alone.

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

A passkey that names no credential must be discoverable, kept by the
authenticator, so registration requires a resident key. It also asks
for the credProps extension, whose answer sesam never reads: Firefox
on Android passes the resident-key requirement on to the phone only
when credProps is asked for, and otherwise makes a passkey that
registers but can never sign in.

## The gate in the core, the routes in Sinatra

Who is calling (Access, Credential, Accept, Settings) needs a Rack env
and nothing more, so it is in the core, for any Rack application; the
routes need a framework, and are a Sinatra extension, loaded on its
own like passkeys. One Settings object carries everything the gate
and the routes read, built once; an unknown key in it is refused
rather than ignored, a typo being a setting silently left at its
default.

sesam reaches users through a store, or a callable yielding one: the
application decides how it opens and locks it, and sesam builds Users
and Passkeys on what it is given, with the reserved names. The
application's part of a change (an audit row) needs the request, so it
is a helper (`sesam_changed`), not a callable in the settings, and it
runs inside the change's transaction so that one is kept only with the
other. A profile (`sesam_profile`) is merged beside sesam's answer and
never over it: one naming a key of sesam's raises, since a display
name answered as `name` would pass for the login.

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
a throw, and a store commits a transaction a throw leaves, so an
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
