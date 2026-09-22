# Versioning — ask-decisions

**This file is the repository's canonical versioning policy.** When this
document and any other doc disagree, this one wins.

## Scheme

[Semantic Versioning 2.0.0](https://semver.org): `MAJOR.MINOR.PATCH`.

## Pre-1.0 (0.x) meaning

While the major is `0`, MINOR may break compatibility and PATCH may not:

- **PATCH** (`0.2.5` → `0.2.6`): bug fixes, internal refactors, docs, and
  tests. No intentional behavior or public API change.
- **MINOR** (`0.2.5` → `0.3.0`): new features, new public API, and any
  breaking change. Breaking changes are called out in the changelog under
  `### Changed` or `### Removed`.
- **MAJOR** (`0.x` → `1.0.0`): the API is declared stable; after 1.0 the
  usual SemVer rules apply (breaking change ⇒ MAJOR, additive ⇒ MINOR,
  fix ⇒ PATCH).

## Sequential patch increments

Patch numbers advance one step at a time: `0.2.5` → `0.2.6` → `0.2.7`.
Never jump patch numbers (no `0.2.5` → `0.2.8`), even when several fixes
land at once — they ship together in a single release. If a patch release
was yanked or skipped in `version.rb`, renumber so the sequence stays
contiguous before the next release.

## Releases go through gemchain

- Every `ask-*` gem (including ask-decisions) and **yamine** is released
  with `gemchain` from the workspace root — never `rake release`,
  `gem build` + `gem push`, or any other hand-rolled release.
- **gemchain itself** is not an `ask-*` gem, so the cascade cannot release
  it; it follows the same release discipline manually (bump `VERSION`,
  changelog, tests, commit, tag, publish, push).
- **Dependency releases use the gemchain cascade**: when a dependency of
  ask-decisions (or a gem that depends on it) changes, run `gemchain guard`
  to see the blast radius and `gemchain update` to bump, test, and release
  every affected gem in topological order. Never release the dependent by
  hand.

## Clean tree required

`git status` must be clean before any release. Commit (or stash) work in
progress first; gemchain commits the release's own changes (version,
changelog, constraint updates) as part of the release.

## Release checklist

Run through every step, in order, for each release:

1. **Tests** — `bundle exec rake test` (and dependents' suites via
   `gemchain update … --test-only` when cascading) passes on a clean tree.
2. **Build** — `gem build ask-decisions.gemspec` succeeds (gemchain does
   this during release; a manual build is a pre-flight sanity check only).
3. **Changelog** — move the `## [Unreleased]` entries under a new
   `## [X.Y.Z] - YYYY-MM-DD` heading; start a fresh empty `## [Unreleased]`
   section at the top.
4. **Commit** — commit the version, changelog, and constraint changes with
   a short message (gemchain does this for you).
5. **Tag** — `git tag vX.Y.Z` on exactly that commit.
6. **Publish** — `gem push` the built gem to RubyGems (gemchain runs this).
7. **Push** — `git push origin HEAD --tags` so the commit and tag are
   remote.

A release is done only when **published AND pushed**.

## Version consistency

After every release these four must agree:

- the **published version** on RubyGems,
- `VERSION` in `lib/**/version.rb`,
- the **git tag** `vX.Y.Z`,
- the **source** at that tag/commit (and at `HEAD` once pushed).

`gemchain check` from the workspace root is the quick audit; an `ORPHANED`
line (published == local, but local ≠ HEAD) means the release was never
committed — fix it immediately.

## Unreleased changelog workflow

While work is in progress, add entries under `## [Unreleased]` in
`CHANGELOG.md` as each change lands (Keep a Changelog format: `### Added`,
`### Changed`, `### Fixed`, `### Removed`). On release day that section is
retitled to the new version and date; never release with unsorted changes
sitting outside `[Unreleased]`, and never leave released changes inside it.

## Examples

Starting version `0.2.5`, all released via
`gemchain update ask-decisions <ver>` from the workspace root:

| Change | Next version | Why |
|---|---|---|
| Fix the compactor dropping a pinned pair | `0.2.6` | pre-1.0 fix ⇒ sequential PATCH |
| Three bug fixes land together | `0.2.7` (one release, not `0.2.8`) | one step, however many fixes |
| Add a new decision policy | `0.3.0` | new feature ⇒ pre-1.0 MINOR |
| Rename a public class (breaking) | `0.3.0` | breaking ⇒ pre-1.0 MINOR |
| Declare the API stable | `1.0.0` | first stable major |
| ask-agent (a dependent) must pick the change up | cascade via `gemchain update ask-decisions <ver>` | dependents handled by the cascade, never by hand |
