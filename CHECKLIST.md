# Closing a round on sesam

## Gates

- [ ] `bundle exec rake` passes: tests, then RuboCop.
- [ ] `gh run list -R sdalu/sesam -L 1` shows the pushed commit's gate
  passed on GitHub, once the repository is there.
- [ ] Does ClimatControl's gate still pass against this tree (its
  Gemfile pointed at the local path), once it uses sesam?

## Documents

- [ ] `README.md`: do its examples still run, and do the table and
  the known shortfalls match the code?
- [ ] `DESIGN.md`: did this round change a reason it gives, or make a
  choice it should record?

## Release

- [ ] Does `Sesam::VERSION` in `lib/sesam/version.rb` move with this
  round? It is the one place the release number is written. The
  owner makes every tag: propose the number, do not tag.
