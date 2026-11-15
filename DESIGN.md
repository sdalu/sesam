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

A passkey ceremony is two requests, and the challenge must reach the
second before any session exists: it rides in a cookie signed the same
way, for five minutes. A challenge nobody can forge is as safe held
by the client.

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

Keys and invitations are 256 random bits, kept as SHA-256 digests: a
fast digest loses nothing against that much entropy, and a lookup by
digest tells a guesser nothing a guess would not. Names an
application keeps for itself (an audit's `root`) are given, not
built in.

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
