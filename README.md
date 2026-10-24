# Heni

Heni runs deliberate mutations and verifies that the intended tests catch them.
Describe a checked edit, build/test commands and a precise failure witness. Heni
first proves the unchanged baseline, then runs the mutation in a disposable copy
and retains a portable report.

Version 0.1.0.0 is unreleased. Local release validation and its limits are recorded
in [release readiness](https://github.com/shinzui/heni/blob/master/docs/validation/release-readiness.md). Ordinary Cabal and
released dependencies are sufficient; repository documentation tools and Nix are
optional. Supported compiler/platform combinations are listed in
[compatibility](docs/design/compatibility.md).

From this checkout:

```sh
cabal build all -j1
cabal run heni-cli:exe:heni -- check examples/minimal/heni.json
cabal run heni-cli:exe:heni -- run examples/minimal/heni.json --case guard-bypass --output .heni-runs/first-caught
cabal run heni-cli:exe:heni -- report .heni-runs/first-caught/report.json
```

Expect `caught` and exit 0. Selecting `--case survivor` with a fresh output path
produces `survived` and exit 1. Configuration or infrastructure failures exit 2.
The [quickstart](docs/quickstart.md) begins with the unchanged passing fixture and
shows both cases. Commands use literal argv; no shell mutation runner is needed.

| Package | Purpose |
| --- | --- |
| `heni` | Framework-neutral `Test.Heni` library, strict manifests, runner and reports. |
| `heni-cli` | The `heni` executable using the same library classifier. |
| `heni-tasty` | Optional complete named-test evidence for Tasty. |
| `heni-hspec` | Optional Hspec evidence and native QuickCheck replay. |

A Haskell consumer constructs `CaseDefinition`, calls `mkCampaign`, then
`runCampaign (defaultRunOptions source output) campaign`. The library returns
`RunResult`; the caller owns application rendering/exits. See the
[short library example](examples/library/Definitions.hs) and the
[independent consumer](examples/standalone/Main.hs). Use generic exact diagnostics
when test counts are unknown, or install a reporter for selected/executed IDs and
named assertions. Tasty/Hspec reporters are optional. Released Aeson brings a transitive
QuickCheck dependency; the core exposes no framework test types.

Heni supports checked UTF-8 replacement, create/delete, optional Git textual
patches and trusted Haskell transformations. Baselines, controls, intentional
compiler rejection, replay and fresh crash probes have separate evidence
contracts. Timeouts, unrelated errors, stale edits and missing test evidence
cannot count as successful semantic detection. Source snapshots include selected
dirty and untracked regular files; the original checkout remains unchanged.

Scoped resources and bounded workers support consumer-owned fixtures. Baseline
sharing is opt-in and requires complete compatible identities. Incremental build
reuse requires a trusted content-observation verifier; there is no generic
portable switch that makes every build cache safe.

The POSIX supervisor bounds commands, output capture and group cleanup. Detached
descendants and runner SIGKILL need stronger consumer containment. Windows, AST
mutation generation, distributed execution, persistent verdict caches and
automatic database rollback are outside this release. Consumer hooks are trusted
code, not a security sandbox.

Read the [CLI reference](docs/cli.md), [troubleshooting](docs/troubleshooting.md),
[adapter contracts](docs/design/adapters.md), [resource/reuse guide](docs/design/scheduling.md),
and [migration guide](docs/migration-guide.md). Versioned [schemas](schemas/) cover
manifests, reports and test evidence. The [migration evidence](docs/validation/migration-results.md)
separates measured fixture results from historical research and future consumer work.

For contributors:

```sh
cabal test all -j1 --test-show-details=direct
sh scripts/test-migrations.sh
sh scripts/check-sdist.sh
```

The archive check additionally needs development-only Python/jsonschema and Git
for the explicit optional patch gate. Core tests run with a tool path excluding
Git, Nix, Mori, OKF and Python. [Release preparation](docs/releasing.md) explains
local archives and the separate later Hackage candidate/publication review.

Heni derives its name from Japanese 変異 (*hen’i*), mutation or variation.
Licensed BSD-3-Clause; copyright 2026 Nadeem Bitar.
