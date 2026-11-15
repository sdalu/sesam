# sesam

How it works: README.md. Why it is shaped so: DESIGN.md. What closes
a round: CHECKLIST.md.

Gate: `bundle exec rake`

Ruby style: the `ruby` skill (4-space indentation, double quotes,
`.rubocop.yml` is its rule set).

## Traps

- Releases are the owner's: never create or push a tag, nor move
  `VERSION`, unasked.
- ClimatControl (~/Repos/ClimatControl, never edited from here: tell
  the ClimatControl session) is the first user, and its stored
  password hashes and live session cookies must keep checking: the
  pinned values in test/password_test.rb and test/session_test.rb are
  its, never to be regenerated to make a test pass.
- base64 is no longer a default gem in Ruby 3.4: it is a dependency
  in the gemspec, or `require "base64"` fails under bundler.
