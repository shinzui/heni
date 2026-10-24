---
type: Guide
title: "Moving a mutation script to Heni"
description: "Migrate existing mutation scripts while preserving consumer-owned faults and witnesses."
docId: DOC-5
tags: ["migration", "scripts", "examples"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:57:52Z
sources:
  - resource: examples/migrations/README.md
  - resource: docs/validation/migration-results.md
---

# Moving a mutation script to Heni

Keep the fault and its assertion in the consumer project. Move snapshotting,
checked edits, baselines, subprocess ownership, attribution and reporting into
Heni. Start with one meaningful case and a precise witness; migrate a service
fixture only after its owner supplies reset and teardown semantics.

The local examples are independently authored BSD-3-Clause fixtures. No code
or license grant was copied from the surveyed consumers, and their repositories
were not modified or executed. The source inventory was refreshed through Mori
on 2026-10-24; exact HEAD/file hashes are in
[the identity record](../validation/migration-source-identities.json). The rdkafka
runner changed after RES-1: its refreshed file has 453 lines rather than the
historical 349. Neither count estimates removable orchestration. File-level
Mori artifact URIs are pending; each relative source path below is paired with
its canonical owner.

| Local family | Surveyed pattern | Fault and witness |
| --- | --- | --- |
| [replacement](../../examples/migrations/replacement/heni.json) | [rdkafka-hs](mori://shinzui/rdkafka-hs/packages/rdkafka-hs), `scripts/test-mutations.hs`; [Shibuya](mori://shinzui/shibuya), `scripts/audit/run-websocket-mutation-controls.py` | Replace one capacity guard; require the full-capacity diagnostic. |
| [patch catalogue](../../examples/migrations/patch-catalogue/heni.json) | [Nagare](mori://shinzui/nagare), `cli/nagare-harness/src/Nagare/Harness/Mutation.hs` and `cli/nagarectl/test/mutations/records.json` | Apply a named checked textual patch; stale patches are invalid mutations. |
| [generated code](../../examples/migrations/generated-code/heni.json) | [Keiro DSL](mori://shinzui/keiro/packages/keiro-dsl), `keiro-dsl/test/history-dependent-holes-mutation-test.sh` | Mutate generator input, generate, compile, then require the generated guard assertion to fail. |
| [diagnostic checker](../../examples/migrations/diagnostic-checker/heni.json) | The external-rule checker pattern in [RES-1](../research/mutation-testing-survey.md) | Change capacity policy; require exit 1 and the exact capacity-rule diagnostic. |

Each checked-in default manifest selects an intended-caught case. The trial
adds a deliberately surviving label change through both independent Haskell
case definitions and the portable manifest. Replacement also distinguishes an
unrelated compile error from an intentional compiler-rejection expectation.
Use a new output directory for every invocation:

```bash
cabal run heni-cli:exe:heni -- run examples/migrations/replacement/heni.json --output .heni-runs/migration-replacement
cabal run heni-cli:exe:heni -- run examples/migrations/patch-catalogue/heni.json --output .heni-runs/migration-patches
cabal run heni-cli:exe:heni -- run examples/migrations/generated-code/heni.json --output .heni-runs/migration-generated
cabal run heni-cli:exe:heni -- run examples/migrations/diagnostic-checker/heni.json --output .heni-runs/migration-diagnostic
```

These examples need released GHC/Cabal, and only the patch family needs Git.
They require no database, broker, Mori, OKF or Nix at runtime. The checker builds
`./dist-newstyle/checker`; availability of explicit workspace executables is
checked after build rather than against the caller's active directory.

For generated code, identify what the edit changes. This fixture edits
`model.txt` before `tools/Build.hs` creates `generated/Generated.hs`. The build
log records the generated definition and the test executes that compiled
module. The test command never regenerates it. Editing generated output before
a build that overwrites it can produce a survivor without testing the intended
fault. Use generator input where possible; otherwise supply a consumer-owned
build/edit workflow that preserves and verifies the generated artifact.

A Haskell consumer can replace a declarative edit with `CustomEdit` and a
`CaseHooks.customEdits` function using checked `WorkspaceOps`. The generated
trial demonstrates that boundary while its CLI equivalent uses `Replace`.
The hook owns the transformation only. It does not copy/restore a checkout,
spawn cleanup loops, or decide the mutation verdict. Arbitrary Haskell hooks
and build observation verifiers cannot be serialized into a manifest.

| Capability | First-release contract |
| --- | --- |
| Checked UTF-8 replacement, create/delete | Direct Haskell and manifest support, ordered exact preconditions. |
| Textual patch catalogues | Optional Git; no rename/copy/mode-only/binary patch claim. |
| Generated artifacts | Input mutation is direct; output ordering/preservation needs a consumer-owned workflow or hook. |
| Generic external checker | Exact stage, exit and byte witness; test counts remain unknown. |
| Named assertions | Optional Tasty/Hspec reporters, complete attempt-bound IDs/counts, no colored-output scraping. |
| Property replay | Native QuickCheck helper with Hspec, one selected replay property per attempt; other native protocols need typed builders. |
| Native crashes | POSIX signal plus a fresh case/stage probe; reachability does not establish arbitrary root cause. |
| Controls and compiler rejection | Explicit separate expectations; an unrelated compiler failure cannot satisfy a semantic assertion. |
| Multi-stage commands | Build/test/replay are supervised; consumer generation/setup commands remain explicit. |
| Shared services | Scoped resources, namespaced bindings, reset/teardown, capacities and meaningful epochs; live service proof belongs to the consumer. |
| Workers and reuse | Private trees, bounded claims; opt-in compatible baselines. Incremental builds need a verified Haskell provider; no universal Cabal timestamp guarantee. |
| Binary files | Snapshot/copy support; no first-release binary mutation vocabulary. |
| Database-state fault injection | External consumer fixture work; filesystem isolation does not roll back a database. |
| Detached processes/cross-process locks | Consumer ownership; the in-process scheduler cannot coordinate separate campaigns. |
| AST operators, distributed execution, persistent verdict cache, Windows | Unsupported in this release. |

Run the combined trial with `sh scripts/test-migrations.sh`. It separately builds
the CLI, then enables the core archive's `migration-tests` flag with
`HENI_CLI_EXE`. Default core tests have no CLI/framework dependency. Repository
release CI runs this explicit integration gate as well as the optional reporter
packages. The Haskell comparison harness in `test/migration/Legacy.hs` is an
independently authored finite measurement fixture with deliberately exit-only
verdicts, not a recommended runner or a copy of production scripts.

The [value record](../validation/migration-results.md) separates executable parity,
consumer definitions/domain helpers, lifecycle scaffolding, automated authoring
and diagnosis actions, and elapsed build time. Automated agent observations are
not a human usability study. Full consumer migrations remain later work: start
with one replacement in its owning project, then a small patch batch, generated
workflows with explicit artifact ordering, and finally live resource cases with
consumer-owned acceptance. No fleet migration has occurred here.
