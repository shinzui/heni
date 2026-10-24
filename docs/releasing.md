# Preparing a release

The bootstrap produces local source/docs archives and a readiness record. It does
not upload candidates, publish packages, push commits or create tags. Recheck the
[readiness record](https://github.com/shinzui/heni/blob/master/docs/validation/release-readiness.md) and current package-name state
before a later release action. An absent package name is not a reservation or an
ownership grant; verify the intended Hackage account's upload permissions.

Use the tested GHC/Cabal combinations in [compatibility](design/compatibility.md).
The four packages share version 0.1.0.0; CLI/reporters require that exact core
version. Public API versioning follows the [PVP](https://pvp.haskell.org/): breaking
API/type/instance changes increase A.B, additive APIs increase C, and fixes may
use the fourth component. JSON schema versions evolve independently. Do not use
`--allow-newer` to replace validation of admitted dependencies.

Run package checks in each package directory and then validate fresh source
archives. Development-only schema validation requires jsonschema 4.26.0.

```sh
cabal build all -j1
cabal test all -j1 --test-show-details=direct
sh scripts/test-migrations.sh
HENI_SCHEMA_PYTHON=/path/to/schema-venv/bin/python sh scripts/check-sdist.sh --bounds lower --output dist-release/lower
HENI_SCHEMA_PYTHON=/path/to/schema-venv/bin/python sh scripts/check-sdist.sh --bounds newest --output dist-release/newest
```

The script records the fresh extraction path, source archive hashes, compiler,
Cabal, each check's exit/duration and solver plans. It retains failed extractions
for diagnosis. Only extracted Heni packages are project sources; other dependencies
come from released repositories. Core-only tests have no CLI/framework closure
or Git/Nix/Mori/OKF/Python executable in their PATH. A separate positive patch gate
requires Git. CLI/reporters, Haddock, schemas, standalone 0/1/2 exit checks and the
four-family migration trial run from archives. Use `--archives DIRECTORY` to
validate an existing immutable archive set on another machine.

The script selectively generates two non-exposed implementation pages so
Haddock's instance-origin links resolve. Their `not-home` attributes keep public
facades as documentation homes; this does not expose package modules or private
constructors. Use the script's Haddock flags when rebuilding release docs.

Inspect generated module pages and source links, command help, examples,
troubleshooting, package contents and dependency plans. Copy accepted Haddock
archives from the fresh extraction's dist-newstyle tree beside the source
archives; record their hashes. Never modify an accepted archive after hashing:
rebuild and rerun relevant gates after source changes. The readiness record and its hashes are repository-only evidence, excluded
from source archives to avoid self-referential archive hashes. Keep those
results under version control; retain large build logs and local tarballs outside
Git. Confirm no credential or secret environment value appears in evidence.

For the separately authorized Hackage step, consult the current official
[Cabal packaging guide](https://cabal.readthedocs.io/en/stable/how-to-package-haskell-code.html)
and [command reference](https://cabal.readthedocs.io/en/stable/cabal-commands.html#cabal-upload).
As checked on 2026-10-24, `cabal upload SOURCE.tar.gz` uploads a candidate by
default; `--publish` immediately publishes. `cabal upload --documentation DOCS.tar.gz`
uploads candidate documentation. Keep authentication in the user's normal secure
Cabal configuration; no credential is part of this validation script or record.

Upload candidates only after that action is authorized. Review each candidate's
rendered documentation, source contents, license, dependency bounds and installability
with all matching Heni candidate archives in a fresh project. A candidate cannot
make another unpublished core version a normal released dependency. Coordinate
publication in dependency order (core, then CLI/reporters) after candidate review;
verify normal Hackage installation and rendered docs afterward. Candidate review,
account authorization, publication and release tags remain explicit handoff items.

Actual consumer migrations are a separate roadmap in [the migration guide](migration-guide.md).
Each owning project must preserve its fault, witness and live resource/reset
contract; local representative fixtures do not establish those migrations.
