---
name: release
description: Release all Heni packages to Hackage following PVP
argument-hint: "[major|minor|patch]"
disable-model-invocation: true
allowed-tools: Read, Bash, Edit, Glob, Grep, Write, AskUserQuestion
---

# Heni Release Skill

Release the Heni packages to [Hackage](https://hackage.haskell.org/) using a
single shared version, following the Haskell PVP (`A.B.C.D`).

## Versioning Strategy

All packages share the **same version number** and are released together. A
single annotated git tag `v<version>` marks each release.

The Haskell PVP version format is `A.B.C.D`:

- `A.B` — **major**: breaking API changes (removed/renamed exports, changed
  types, changed semantics).
- `C` — **minor**: backwards-compatible API additions (new exports, new
  modules, new instances).
- `D` — **patch**: bug fixes, documentation, internal-only changes,
  performance improvements.

## Packages (in dependency order)

The packages MUST be published in this order due to inter-package
dependencies. `heni` is the core library; the other three each depend on it
and have no dependencies on one another:

1. **heni** — core library (`.`, cabal file `heni.cabal`). No internal deps.
2. **heni-cli** — CLI executable (`heni-cli/`). Depends on `heni`.
3. **heni-tasty** — optional Tasty reporter (`adapters/heni-tasty/`). Depends on `heni`.
4. **heni-hspec** — optional Hspec reporter (`adapters/heni-hspec/`). Depends on `heni`.

> Items 2–4 depend only on `heni`, so after `heni` is published they may be
> uploaded in any order; publish them in the order above for a stable report.

The following are **NOT released** to Hackage:

- Everything under **`examples/`** (`heni-minimal-fixture`,
  `generated-fixture`, `examples/standalone/consumer`, and the other migration
  fixtures) — these are test fixtures and example consumers, not in
  `cabal.project`'s `packages:` list, and have no Hackage metadata.

## Arguments

`$ARGUMENTS` is optional:

- `major`, `minor`, or `patch` — specifies the bump level.
- If omitted, determine the bump level from the changes (see step 2).

## Steps

### 1. Determine what changed since the last release

- Read the current version from `heni.cabal` (all packages share it; confirm
  the other three cabal files match).
- Find the latest git tag matching `v*` to identify the last release point:
  `git tag --list 'v*' | sort -V | tail -1`. **There may be no tags yet** —
  this repo has not cut a release. If so, treat all history as the first
  release and skip the "commits since tag" diff.
- With a prior tag, run `git log --oneline <last-tag>..HEAD` to list commits
  since the last release. If there are none, tell the user there is nothing to
  release and stop.

Present a summary showing: current version, last release tag (or "none —
first release"), number of commits since last release, and which package
directories changed.

### 2. Determine the next version using PVP

Rules:

- If `$ARGUMENTS` is `major`, `minor`, or `patch`, use that bump level.
- Otherwise analyze the commits to determine the bump. These commits follow
  [Conventional Commits](https://www.conventionalcommits.org/):
  - `feat!:` / `BREAKING CHANGE:` / "remove", "rename", "change type" → **major**
  - `feat:` (new exports/modules/features) → **minor**
  - `fix:`, `docs:`, `refactor:`, `chore:`, `test:`, `build:`, internal-only → **patch**
- Present the proposed bump to the user and ask for confirmation before
  proceeding.

Increment the version:

- **major**: increment `B`, reset `C` and `D` to 0 (`0.1.0.0` → `0.2.0.0`)
- **minor**: increment `C`, reset `D` to 0 (`0.1.0.0` → `0.1.1.0`)
- **patch**: increment `D` (`0.1.0.0` → `0.1.0.1`)

> First release note: the packages currently sit at `0.1.0.0` with
> `(unreleased)` changelog headers. The first release may simply publish
> `0.1.0.0` as-is (no bump) — confirm with the user whether this release
> finalizes `0.1.0.0` or bumps from it.

### 3. Update versions, internal bounds, and changelogs

#### Version update

Set the new version in all four cabal files:

- `heni.cabal`
- `heni-cli/heni-cli.cabal`
- `adapters/heni-tasty/heni-tasty.cabal`
- `adapters/heni-hspec/heni-hspec.cabal`

#### Internal dependency bounds

`heni-cli`, `heni-tasty`, and `heni-hspec` each pin the core library exactly
as `heni ==<version>`. Update that bound to the new version everywhere it
appears (library **and** executable/test-suite `build-depends` sections).
Also check for an internal `heni-tasty ==` / `heni-hspec ==` pin in their own
fixture executables and bump those too. Keep the project's existing exact-pin
style (`==<version>`) unless the user asks to switch to PVP caret bounds
(`^>=`).

> Grep to catch every occurrence:
> `grep -rn 'heni[a-z-]* *==' heni.cabal heni-cli adapters`

#### Changelogs

Each package has a `CHANGELOG.md`; there is also a root `CHANGELOG.md`. They
use a header convention of `# <version> (unreleased)` with a prose summary.

- Replace the `(unreleased)` marker on the current top section with the real
  version and today's date, or add a new `# <version> — YYYY-MM-DD` section
  above previous entries if the top section was already released.
- Summarize the commits since the last release, grouped (only include
  categories that have entries):
  - **Breaking Changes** (major)
  - **New Features** (minor or major)
  - **Bug Fixes**
  - **Other Changes** (docs, refactoring, build)
- Update the root `CHANGELOG.md` and each affected per-package `CHANGELOG.md`.

Show the user **all** changes (version bumps, internal bounds, changelog
entries) for review before committing.

### 4. Verify builds and checks

Run these gates in order; fix any failure before continuing:

1. `nix fmt` — formats via treefmt (nixpkgs-fmt + fourmolu + cabal-gild).
2. `cabal build all` — verify the whole workspace builds.
3. `cabal test all` — run every test suite (heni-unit, heni-runner,
   heni-process, heni-adapter, heni-workspace, heni-scheduler, heni-migration,
   heni-cli-test, heni-tasty-test, heni-hspec-test).
4. `nix flake check` — treefmt + git-hooks (incl. the commit-message
   newline-escape guard) and the flake's package/check outputs.
   - Newly created files (e.g. a fresh `CHANGELOG.md`) must be `git add`-ed
     first, since nix evaluates the git tree.

### 5. Commit, tag, and push

- Stage all modified `.cabal` and `CHANGELOG.md` files.
- Create one commit with a Conventional Commits message: `chore(release):
  <new-version>`. The body should summarize the release contents and justify
  the chosen bump. Use real line breaks (the commit-msg hook rejects literal
  `\n` escapes).
- Create one annotated tag: `git tag -a v<version> -m "Release <version>"`.
- Push: `git push && git push --tags`.

### 6. Publish to Hackage (in dependency order)

For EACH package, in dependency order (**heni → heni-cli → heni-tasty →
heni-hspec**):

1. `cd <pkg-dir>` (root `.` for `heni`).
2. `cabal check` — verify no packaging issues.
3. `cabal sdist`, then `cabal upload --publish <tarball-path>` to publish the
   source distribution.
4. `cabal haddock --haddock-for-hackage --haddock-hyperlink-source --haddock-quickjump`,
   then `cabal upload --publish --documentation <docs-tarball-path>`.
5. Report the Hackage URL: `https://hackage.haskell.org/package/<pkg>-<version>`.

After all uploads, present a summary table:

| Package | Version | Hackage URL |
|---------|---------|-------------|
| heni | X.Y.Z.W | https://hackage.haskell.org/package/heni-X.Y.Z.W |
| heni-cli | X.Y.Z.W | https://hackage.haskell.org/package/heni-cli-X.Y.Z.W |
| heni-tasty | X.Y.Z.W | https://hackage.haskell.org/package/heni-tasty-X.Y.Z.W |
| heni-hspec | X.Y.Z.W | https://hackage.haskell.org/package/heni-hspec-X.Y.Z.W |

### 7. Create the GitHub release

After all Hackage uploads succeed, create a GitHub release for the tag:

```bash
gh release create v<version> --title "v<version>" --notes "$(cat <<'EOF'
## Packages

| Package | Hackage |
|---------|---------|
| heni | https://hackage.haskell.org/package/heni-X.Y.Z.W |
| heni-cli | https://hackage.haskell.org/package/heni-cli-X.Y.Z.W |
| heni-tasty | https://hackage.haskell.org/package/heni-tasty-X.Y.Z.W |
| heni-hspec | https://hackage.haskell.org/package/heni-hspec-X.Y.Z.W |

## What's Changed

<changelog entries for this version from the root CHANGELOG.md>
EOF
)"
```

- Use the root `CHANGELOG.md` entries for the release-notes body.
- Report the GitHub release URL when done.

## Important

- Always ask the user to confirm the version bump and changelogs before
  committing.
- Always publish in dependency order: **heni first**, then the dependents.
- When bumping, always update the internal `heni ==<version>` bounds in
  `heni-cli`, `heni-tasty`, and `heni-hspec` to match.
- Never skip `cabal check`, `cabal test all`, or `nix flake check`.
- If any step fails (including `nix flake check`), stop and report the error
  rather than continuing.
- If a Hackage upload fails for `heni`, do NOT continue uploading the
  dependents that require it.
- Run `nix fmt` before committing, and `git add` new files before
  `nix flake check`.
- The commit and tag are created only AFTER the user approves all changes.
