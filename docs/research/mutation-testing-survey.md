---
type: Research Document
title: Mutation testing across Haskell projects and the case for Heni
description: Evaluate existing mutation runners, identify reusable contracts, and bound a public Haskell library and CLI.
generated:
  by: process:codex
  at: "2026-10-24T14:01:14Z"
researchId: RES-1
status: complete
scope: >-
  Source inspection of mutation infrastructure in Nagare, Keiro, rdkafka-hs,
  and Shibuya, with a discovery scan of 148 Mori-registered project paths in
  the shinzui and tan namespaces and selected adjacent checker tests. Counts
  and primary-source identities were refreshed on 2026-10-24. Existing reports
  were read; mutation suites were not rerun. This is an extraction assessment,
  not an exhaustive ecosystem survey or a measured productivity benchmark.
reviews:
  - kind: model
    reviewer: process:codex
    reviewed_at: "2026-10-24T14:08:32Z"
    document_timestamp: "2026-10-24T14:01:14Z"
    scope: content-and-metadata
    outcome: commented
    provider: openai
    model: gpt-6
    effort: unspecified
    context: >-
      Author self-review of source counts, primary file fingerprints, stage
      classification examples, canonical references, and stated evidence limits.
      This is not independent review or an approval attestation. Source suites
      were not rerun and future API feasibility remains unverified.
sources:
  - id: nagare
    resource: mori://shinzui/nagare
    title: Mutation manifest, Haskell harness, and incremental sweep workers
  - id: keiro
    resource: mori://shinzui/keiro/packages/keiro-dsl
    title: Generated-code and DSL conformance mutation scripts
  - id: rdkafka
    resource: mori://shinzui/rdkafka-hs/packages/rdkafka-hs
    title: Consolidated semantic mutation runner and parity evidence
  - id: shibuya
    resource: mori://shinzui/shibuya
    title: WebSocket and queue mutation controls
  - id: profiles
    resource: mori://shinzui/okf-profiles
    title: Product-discovery fixture mutations and precise diagnostic checks
  - id: kenshou
    resource: mori://shinzui/keiro-runtime-kenshou
    title: Checker self-tests using doctored ledgers
  - id: kikan
    resource: mori://shinzui/kikan
    title: Inline-document contract fixture mutation tests
  - id: keiki
    resource: mori://shinzui/keiki
    title: Reusable shape-hash sensitivity tests
  - id: kotei
    resource: mori://shinzui/kotei
    title: Release-feature validator self-tests
  - id: kiroku
    resource: mori://shinzui/kiroku
    title: Benchmark acceptance validator fault checks
  - id: mls
    resource: mori://tan/mls-reconciler
    title: Database-state and schema fault cases for chapter synchronization
  - id: cabal
    resource: https://cabal.readthedocs.io/en/stable/cabal-commands.html
    title: Cabal package checks, source distributions, documentation, and uploads
  - id: pvp
    resource: https://pvp.haskell.org/
    title: Haskell Package Versioning Policy
---

# Mutation testing across Haskell projects and the case for Heni

## Question and conclusion

Would a shared Haskell library save effort across the existing Bash, Python, and
Haskell mutation runners, and could it be useful to the wider Haskell ecosystem?

**The source evidence justifies a small shared execution library with a CLI.**
The repeated work is preparing a baseline, isolating and applying a deliberate
fault, invoking the appropriate build/tests, attributing the failure, restoring
the candidate, and preserving evidence. The faults and expected diagnostics
remain project-specific.

The public product should make one useful mutation easy to define, work with
existing test suites, and run from ordinary Cabal packages. Hackage publication
is an explicit project goal. Internal repository conventions are evidence for
the design, not required infrastructure for downstream users.

This completed record captures a bounded investigation. Its review entry records
an author self-review, not independent approval; no verification attestation is claimed.
Implementation feasibility, developer-time savings, and runtime improvements
remain to be established through prototypes and migration trials.

## Method and evidence boundary

Mori located the owning repositories and documentation. A filename and tracked
code-content scan covered 148 registered project paths in the `shinzui` and
`tan` namespaces under the local project tree. The scan found candidates;
selected source files were then read to distinguish test sensitivity from
ordinary application/database operations also called mutations.

This scan can miss unregistered repositories, ignored or untracked scripts,
different terminology, and ephemeral investigation scripts. It is sufficient
to establish repeated implementations, not a complete inventory of all uses.
No mutation suite, broker, database, remote builder, or timing benchmark was run
for this investigation. Existing success reports are historical evidence, not
fresh verification.

Primary source snapshots refreshed while capturing this record:

| Project | Inspected HEAD | Working-tree qualification |
| --- | --- | --- |
| [Nagare](mori://shinzui/nagare) | `4c99ffe3df84af1f16a2161944ac790197dd63fa` | Clean. |
| [Keiro](mori://shinzui/keiro) | `e6ef560b0a8db0dc091d0f8d7da1bb08c29155be` | Clean. |
| [rdkafka-hs](mori://shinzui/rdkafka-hs) | `5a80c66d7dcccc74062e14f146d18d32b33587ff` | Checkout contained unrelated manifest/plan edits; the inspected runner and parity record were unmodified. |
| [Shibuya](mori://shinzui/shibuya) | `0967f450b659b48d24cb49f199718451a65d2d48` | Clean. |

The file lists below are paired with canonical project/package URIs. File-level
artifact URI coverage is pending; retain the owning URI with each relative path.
The package URI for the Nagare harness was not resolvable in the local registry
at inspection time, so its owning project URI is used.

## Primary implementations

### Nagare: a patch catalogue and staged proof runner

In [Nagare](mori://shinzui/nagare), the relevant files are
`cli/nagare-harness/src/Nagare/Harness/Mutation.hs`,
`cli/nagarectl/test/mutations/records.json`, and `nix/test-runs.nix`.[^nagare]

The manifest contains **189 records: 188 `test-fails` and one `build-fails`**.
Each patch has a record name, suite, test pattern, and expected failure stage.
The fast gate checks catalogue consistency, duplicate names, patch applicability,
and whether patterns select tests. The Haskell result model distinguishes killed,
survived, wrong-stage, stale, and not-run records.

The remote sweep prepares one workspace and baseline build per worker, then
patches, builds incrementally, tests a selected pattern, and reverses the patch.
Source comments describe the full-rebuild cost and explain the incremental
strategy; those timings were not independently measured here.

Two gaps are visible in the source. `classifyProof` accepts any failed test-stage
exit as a kill; the sweep uses `timeout 1800`, so a timeout exit can be classified
as detection. Also, `selectRecords` follows changes to patch files, their source
targets, and the manifest, without generally tracking which changed test files
could weaken a mutation's detector. A shared runner should separate timeouts and
include test changes in any conservative impact selection.

### Keiro: repeated shell orchestration with improving attribution

In [Keiro's DSL package](mori://shinzui/keiro/packages/keiro-dsl),
`keiro-dsl/test/*mutation-test.sh` contains **21 top-level scripts totaling 1,558
lines**, excluding four additional mutation helper scripts in a fixture
subdirectory. The total includes consumer-specific faults and assertions as
well as orchestration; it is not an estimate of removable code.[^keiro]

Repeated code includes temporary backups, restoration traps, baseline runs,
embedded Python/sed/perl edits, command exit capture, diagnostic matching, and
post-restoration checks. The cases cover generated transducers, behavior holes,
replay, structural/nominal mappings, and DSL validation.

The older `keiro-dsl/test/mutation-test.sh` accepts any failed `cabal test`,
despite describing a specific named assertion in its comment. An unrelated build
failure can satisfy its success branch. Newer scripts, including
`keiro-dsl/test/history-dependent-holes-mutation-test.sh` and
`keiro-dsl/test/mapped-register-construction-mutation-test.sh`, check precise
named failures or diagnostics; some also hash or compare restored bytes.

Many scripts modify the active checkout and later copy backups over it. That
restoration strategy can interfere with concurrent editing or another mutation
run. Disposable workspaces would remove this recurring source of coordination
risk while preserving the project-owned mutation definitions.

### rdkafka-hs: an existing compact Haskell extraction candidate

In [rdkafka-hs](mori://shinzui/rdkafka-hs/packages/rdkafka-hs),
`scripts/test-mutations.hs` is a **349-line Haskell runner** with five families:
producer, seek, property, topic, and callback. It defines **37 mutations and
seven unchanged controls**.[^rdkafka]

The runner makes an isolated source distribution, resets edited sources between
cases, checks replacement anchors, builds each candidate, and requires a named
regression failure. Property cases record and rerun generated counterexamples.
Certain native lifetime faults explicitly permit a signal failure after a
case-specific safety marker. Evidence includes logs, revision, source fingerprint,
archive hash, and native library version.

`docs/testing/mutation-runner-parity.json` reports parity for 32 original
mutations and five controls, plus five new callback mutations and two controls.
That is evidence of a previous consolidation from separate runners. Its results
were inspected, not rerun or recertified against the refreshed HEAD.

This is a useful starting point for extracting common orchestration, but it is
still specialized: source archive layout, Cabal component names, output parsing,
fingerprint inputs, native crash probes, and replay conventions belong to this
consumer. Generalization should expose those choices explicitly.

### Shibuya: the same pattern in Python

In [Shibuya](mori://shinzui/shibuya),
`scripts/audit/run-websocket-mutation-controls.py` applies three behavioral
controls to queue and WebSocket implementation code. It requires a disposable
checkout, edits known anchors, runs focused tests with a timeout, restores in a
`finally` block, and records source hashes and results.[^shibuya]

Its failure check combines a nonzero exit with evidence that examples ran.
That is stronger than accepting an arbitrary build failure, but weaker than
requiring the exact named assertion. It independently repeats the same core
responsibilities as the Haskell and shell runners.

## Adjacent patterns and their limits

| Source | Observed pattern | Implication for Heni |
| --- | --- | --- |
| [OKF Profiles](mori://shinzui/okf-profiles), `scripts/test-product-discovery.py` | Copies fixture trees, applies exact-count edits, requires exit 1 and the expected rule/source/field diagnostic, rejects unrelated rule errors, and checks the restored baseline. | A strong model for diagnostic expectations over external commands.[^profiles] |
| [Kenshou](mori://shinzui/keiro-runtime-kenshou), `kenshou-check/src/Kenshou/Check/Selftest.hs` | Nine deliberately doctored ledgers must produce checker violations. | Useful sensitivity controls; they can remain lightweight in-process tests.[^kenshou] |
| [Kikan](mori://shinzui/kikan), `docs/architecture/evolution/conformance/inline-document-conversations/test_verify.py` | Copies contract fixtures, changes them, refreshes the manifest, and checks semantic rejection codes. | Fixture mutation needs the same attribution discipline as source mutation.[^kikan] |
| [Keiki](mori://shinzui/keiki), `keiki-codec-json-test/src/Keiki/Codec/JSON/Test.hs` | A reusable helper checks that schema-shape variations change the hash. | Evidence that small domain-specific sensitivity helpers are already useful; no subprocess runner is needed for every case.[^keiki] |
| [Kotei](mori://shinzui/kotei), `scripts/check-release-features.py` | Four altered inventory variants must be rejected. | Keep simple validator self-tests small.[^kotei] |
| [Kiroku](mori://shinzui/kiroku), `bench/mp13-release/test-validation.py` | Twelve altered evidence fixtures must raise validator errors. | Evidence corruption is adjacent to mutation testing, with distinct domain assertions.[^kiroku] |
| [MLS Reconciler](mori://tan/mls-reconciler), `scripts/test_chapter_sync.py` | Alters database state/schema and checks refusal without changing target snapshots. | External fault injection has fixture and side-effect obligations that workspace isolation alone cannot solve.[^mls] |

Do not count every occurrence of “mutation” as program mutation testing. Database
DML, application commands, schema-evolution fixtures, and adversarial inputs may
test product behavior directly. They inform extension points but do not all
justify migration to a shared runner.

## Reusable contract and extraction recommendation

The common abstraction is a case with a stable identity, deliberate change,
passing baseline, selected execution, expected detection, and evidence. Shared
infrastructure can own isolation, checked edits, stages, process budgets,
classification, restoration, controls, and reports. Consumers should own fault
meaning, exact diagnostic/test expectations, fixtures, and service setup.

A CLI makes that infrastructure available to Python and shell callers; a Haskell
API supports typed custom cases without requiring subprocess manifest generation.
Both should call one runner and one classifier. Separate library and CLI packages
keep command-line dependencies out of library consumers.

The existing code is enough to justify an extraction prototype. It does not yet
establish the best generic API or a numerical return on investment. Start with a
checked replacement case, a patch catalogue case, a generated-code mutation, and
an external checker diagnostic case. Compare before/after behavior, including
deliberately broken infrastructure, empty selection, wrong diagnostics, and
timeouts. Measure authoring effort and runtime separately.

The likely savings are in repeated orchestration, maintenance, and failure
diagnosis. Compilation, test runtime, fixture costs, and choosing meaningful
faults remain. Automatic generation and remote scheduling can be added later
when real consumers establish their contracts.

## Public-package implications

The initial public product should need only Cabal and its declared runtime
tools, provide runnable examples for existing Haskell test suites, and explain
the distinction between a survivor and an unverifiable run. A documented
Haskell API, versioned interchange formats, complete reports on failure, and
predictable CI exits are central to its usefulness.

Release readiness includes successful builds from source archives, package
checks, Haddock, verified examples, tested dependency bounds, a supported GHC/OS
matrix, package metadata and licensing, and candidate review. These are design
criteria informed by Cabal's package tooling and the PVP.[^cabal][^pvp]

The [initial specification](../initial-spec.md) makes these proposed contracts
explicit. It is a design artifact, not a claim that the package exists on
Hackage or that its proposed commands already run.

## Evidence fingerprints

SHA-256 of the primary inspected files, allowing the source observations to be
compared with later revisions:

| Owning project | Relative path | SHA-256 |
| --- | --- | --- |
| [Nagare](mori://shinzui/nagare) | `cli/nagare-harness/src/Nagare/Harness/Mutation.hs` | `bb16987bb45e18b609bf1c7e5bbd2bb0b07ae9b67aef01507d97a8cec8485f6b` |
| [Nagare](mori://shinzui/nagare) | `nix/test-runs.nix` | `650a318671a0ff31622455252e552722095e6dbe8042ee07a487cf29e2e3c658` |
| [Nagare](mori://shinzui/nagare) | `cli/nagarectl/test/mutations/records.json` | `f412a0c4191d90e60c47716d222f26bd56473c22278ca993e40b56aeacbcdd63` |
| [Keiro](mori://shinzui/keiro) | `keiro-dsl/test/mutation-test.sh` | `1aa082f1df2730db8087f005ea8c9b6077e5bc13ad3402e5f813ca90914aaa47` |
| [Keiro](mori://shinzui/keiro) | `keiro-dsl/test/history-dependent-holes-mutation-test.sh` | `a7b25458f41c9c2953877b3d4c8d4b0f8d98e5ac4f4ab4522a51b9777b7c2a08` |
| [Keiro](mori://shinzui/keiro) | `keiro-dsl/test/mapped-register-construction-mutation-test.sh` | `be7ff63c33580429f1e81b790055d17cf87b9d44a45fd73f043ecf2a5752a4f2` |
| [rdkafka-hs](mori://shinzui/rdkafka-hs) | `scripts/test-mutations.hs` | `c4959158e199fad5d2148a90f6201ae679a4f153a2979ca05c58ff074dd790b6` |
| [rdkafka-hs](mori://shinzui/rdkafka-hs) | `docs/testing/mutation-runner-parity.json` | `7a5f7a136c7d7ec761678cc511e2e9ecbbb671273cf677275ac2133de3b11349` |
| [Shibuya](mori://shinzui/shibuya) | `scripts/audit/run-websocket-mutation-controls.py` | `f6201fe05cfbff1ca73cc9fff3e24ba2196a4631cc9825c8eca9e87f22634b55` |

[^nagare]: Source files listed under the canonical Nagare project above; no sweep was executed.
[^keiro]: Top-level script count and line count refreshed directly from the DSL test directory.
[^rdkafka]: Runner source and the existing parity JSON; historical results were not rerun.
[^shibuya]: Python runner source, inspected without executing its mutations.
[^profiles]: Product-discovery mutation table, `check_rules`, and `check_mutations` inspected directly.
[^kenshou]: `nonVacuityVerdict` and its targeted checker/fact pairs inspected directly.
[^kikan]: Contract verifier test documentation and fixture-copy/mutate helpers inspected directly.
[^keiki]: `regFileShapeSensitivitySpec` and its documented shape variations inspected directly.
[^kotei]: `--self-test` mutation list and validator rejection loop inspected directly.
[^kiroku]: `test_rejects_faults` fixture mutations inspected directly.
[^mls]: SQL/schema fault loop and unchanged-target snapshot assertions inspected directly.
[^cabal]: [Cabal command reference](https://cabal.readthedocs.io/en/stable/cabal-commands.html), consulted for the role of package checks, distributions, documentation, and uploads.
[^pvp]: [Haskell Package Versioning Policy](https://pvp.haskell.org/), consulted for public API versioning.
