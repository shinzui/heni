---
id: 10
slug: reuse-incremental-cabal-builds-across-worker-baselines-and-candidates
title: "Reuse incremental Cabal builds across worker baselines and candidates"
kind: exec-plan
created_at: 2026-10-30T13:09:46Z
intention: "intention_01m66evactef78brqn46dzxeq6"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-30T13:09:46Z
---


# Reuse incremental Cabal builds across worker baselines and candidates

This ExecPlan is a living document. Update Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective during implementation. Follow `agents/skills/exec-plan/FRICTION.md` for implementation friction and distill durable decisions into `docs/adr/` before completion.

## Purpose / Big Picture


Implement `docs/improvement-requests/reuse-one-incremental-cabal-build-per-worker-across-baselines-and-candidates.md` (IR-1). A manifest author will opt into Cabal reuse and run many different baseline test selectors and mutations using one private incremental build directory per worker. A cold build starts without that directory; an incremental build updates existing artifacts. For a campaign with one stable build contract and no infrastructure failures, N cases on W workers must cause at most W cold builds, including cases with distinct selectors, compile rejection, and stale edits. Fresh execution remains the default and the reference for verdict parity.

The delivered example and regression suite must show actual Cabal builds, matching fresh/reused verdicts, and refusal of stale or missing successful-build receipts before any test executes. A receipt is a small completion record, not proof that the compiler's invalidation algorithm is correct.

## Progress


- [ ] Changed-input restoration preserves unchanged files and detects unexpected state, with adversarial filesystem tests passing.
- [ ] Baselines and candidates share private worker builds under explicit contracts, with selector-specific baseline evidence and retirement tests passing.
- [ ] A manifest-accessible Cabal provider has supervised execution, success receipts, explicit failure semantics, strict decoding, and report trust metadata.
- [ ] A real Cabal campaign proves cold-build counts and fresh/reused parity; guides, schema, ADRs, and required checks are complete.

## Surprises & Discoveries


## Decision Log


2026-10-30: Accept Cabal reuse as an explicit trusted-tool contract. Report that successful execution and source identity are checked while incremental artifact correctness is delegated to Cabal/GHC. Retain existing custom-provider verification semantics; do not silently weaken them.

2026-10-30: Share baseline build artifacts separately from baseline test results. Keep selectors in the existing baseline-result key. Use the current per-case scheduling order; after a mutation, restore baseline inputs and invoke an incremental build before a new baseline test. A previous baseline success alone cannot authorize testing mutated artifacts. “Once per worker” means one cold initialization, not skipping required incremental restoration builds.

2026-10-30: Keep full unexpected-state inventories while optimizing writes. Removing independent integrity checks or introducing cross-run caches is outside scope. Infrastructure retirement or a changed build contract can require another cold initialization; report those explicitly rather than claiming the W bound for such runs.

## Outcomes & Retrospective


## Context and Orientation


`src/Test/Heni/Runner.hs` owns execution and classification inputs. `runOne` currently calls `executeBaseline` inside `withWorkspace snapshot`, then uses `Build.withBuildCandidate` only for candidates. `BaselineKey` includes snapshot, commands, selector, expectation, evidence mode, inherited environment, prepared resources, and reuse policy. `src/Test/Heni/Internal/Baseline.hs` shares only passing baseline facts across a campaign. This result cache is distinct from retaining compiled artifacts.

`src/Test/Heni/BuildReuse.hs` defines the public four-field `BuildReuse` provider and private `BuildWorker`. It resets on command/environment changes, checks source inventories before and after execution, and calls a consumer verifier. `withBuildCandidate` currently deletes every non-retained top-level entry and materializes the whole staged inventory. `src/Test/Heni/Internal/Files.hs` defines `Inventory`, mapping relative names to bytes and executable bits, and supplies checked paths, inventories, and materialization. `src/Test/Heni/Workspace.hs` owns immutable snapshots and disposable directories. Never change the active checkout to run a mutation.

The runner currently calls `confirmBuild` for every normal exit, including nonzero exits. `test/scheduler/Main.hs` explicitly requires verified compiler-rejection evidence. Its existing custom provider tests also assert separate baseline workspaces; update those assertions only for providers that explicitly opt into baseline build sharing. `test/fixture/Main.hs` supplies subprocess behaviors for scheduler tests. `src/Test/Heni/Manifest.hs` currently lowers only workers, resources, and baseline-result reuse into `RunOptions`; `schemas/manifest-v1.schema.json` and `heni-cli/test/corpus/` describe and test that boundary.

Relevant decisions were read after scanning ADR headings: [ADR 2](../adr/2-evidence-owned-classification.md) requires infrastructure errors to take precedence over detection; [ADR 3](../adr/3-immutable-snapshots-and-staged-edits.md) requires immutable input snapshots and checked restoration; [ADR 5](../adr/5-campaign-ledger-and-report-trust.md) requires supervised commands and honest report provenance; [ADR 6](../adr/6-explicit-portable-wire-boundaries.md) requires strict portable decoding and shared library behavior; [ADR 7](../adr/7-attempt-bound-test-evidence.md) binds test evidence to actual attempts; [ADR 8](../adr/8-scoped-resources-and-conservative-reuse.md) requires conservative resource-aware reuse. ADR 8 currently permits only Haskell providers and stronger content observation. Revise that exclusion for this named, weaker trusted-tool provider while preserving the other guarantees.

Dependency research used Mori to discover `mori://haskell/cabal/packages/cabal-install` and `mori://haskell/cabal/repos/cabal`. The latter's project-relative `cabal-install/src/Distribution/Client/FileMonitor.hs` (artifact-level URI pending) contains `checkFileModificationTimeAndHashUnchanged`: equal modification times return unchanged without hashing. Therefore do not assume same-size/equal-time edits automatically invalidate Cabal. Inspect the installed version and prove timestamp handling with the native fixture. No dependency bound or version pin is chosen by this plan. Before introducing any version restriction or workaround, verify releases against Hackage and upstream tags as well as Mori's local source.

## Plan of Work


### Milestone 1: Restore only changed inputs


Add a checked inventory-difference operation in `src/Test/Heni/Internal/Files.hs` and use it in `src/Test/Heni/BuildReuse.hs`. After independently validating the previous worker inventory, compare it with the staged inventory. Remove deleted files, write added or byte-changed files, and update executable bits without rewriting equal bytes. Handle file-to-directory and directory-to-file changes by deleting obsolete descendants before creating replacements. Remove obsolete empty directories where needed. All operations stay beneath the owned workspace and outside retained directories; reject symlinks and special files using existing checked-path rules.

On initial creation or retirement, retain the current full reset. Reject selected source paths overlapping retained roots rather than silently losing them. Preserve the post-restoration, post-preparation, and post-action inventories. Failed restoration retires the worker. Add coverage to `test/workspace/Main.hs` and `test/scheduler/Main.hs` proving unchanged files retain timestamps and identity, changed bytes/modes and deletions are correct, and unexpected files or links fail closed. Passing these suites independently completes this milestone.

### Milestone 2: Separate baseline builds from baseline test results


Introduce explicit baseline-sharing capability for a build provider. Preserve the existing `BuildReuse` constructor and its four-field custom-provider behavior, for example by adding a separate Cabal constructor and internal accessor functions rather than adding mandatory fields to the existing constructor. Define a worker contract including snapshot, provider/toolchain identity, effective build command (argv, cwd and environment), inherited environment, and resource identities/versions/epochs. Compare secret-bearing values only in memory. Never let changes in these values reuse a previous success. Unknown resource epochs and custom hooks disable baseline build skipping conservatively.

For opted-in providers, stage the unchanged snapshot in the retained workspace using the same checked transition as a candidate. Track the currently successful built input identity and its owner build event. Only skip a baseline build when that identity and the full contract still match and verification succeeds again. Otherwise run the unchanged build incrementally, verify it, and only then run the selector's baseline test. A different selector must still get its own test and selection check unless the existing complete `BaselineKey` matches a cached result. Keep resource preparation before baseline and candidate, cleanup accounting, cancellation, and structured producer checks intact.

For the Cabal contract, selectors are test-only: omit `HENI_SELECTOR` from baseline and candidate build environments while preserving it for tests/replays. Document this opt-in promise and keep existing generic/custom behavior unchanged. Do not remove a selector from a key while still passing it to a potentially selector-dependent build command. Reused baseline test facts do not imply a worker is built; the candidate path must still stage, build and verify its own inputs.

A failed or unverifiable baseline build retires retained state and clears its successful-build marker. Keep baseline failures distinct from infrastructure verification failures. Timeouts, cancellation, source mismatch, resource mismatch and cleanup failures retire state. Ordinary compiler rejection with trustworthy execution evidence does not itself require wiping Cabal's directory. Add scheduler tests for multiple selectors, resource/command/environment changes, cached baseline facts on a cold second worker, failed baselines, cancellation, and cleanup. Report owner references for skipped builds without inventing process events or test attempts.

### Milestone 3: Provide the Cabal execution contract


Create `src/Test/Heni/BuildReuse/Cabal.hs` and expose it in `heni.cabal`. Provide `cabalBuildReuse :: Text -> Either ConfigError BuildReuse`, validating a nonempty toolchain identity. Retain only worker-private `dist-newstyle` and `.heni-build`. Initially support Cabal builds rooted at the workspace with the default build directory; reject unsupported cwd/build-directory overrides with actionable configuration errors instead of allowing artifacts outside ownership. The caller promises all relevant package inputs are in the snapshot and the declared build covers every selected test. Document external mutable dependencies as outside this contract.

Implement the provider wrapper around the existing supervised build-stage runner, not a shell string or an unsupervised child process. It receives the validated workspace, current input identity, and actual process outcome. Remove the prior success receipt before invoking the declared command. On a successful build with no supervisor errors and matching source inventory, atomically publish a versioned receipt under `.heni-build/` containing input identity, contract identity and a fresh invocation token. Verify all three against runner-owned current state immediately before tests. Missing, stale, malformed or symlinked receipts produce `InfrastructureError` and zero test invocations. A receipt cannot authenticate its own freshness by supplying the expected token.

Handle normal nonzero exits separately: never write a success receipt or run tests. The Cabal provider's explicit weaker contract accepts the current supervised invocation, unchanged staged inputs and actual exit/diagnostic evidence as failed-build observation. Feed that evidence through the existing classifier, preserving both expected `BuildRejection` and unexpected compile-failure behavior. Existing custom providers still run their verifier on nonzero exits. This distinction must appear in documentation and report metadata; a global “verify only successful exits” change is unacceptable.

Implement conservative timestamp preparation for changed Cabal inputs. Ensure actual filesystem-observed modification times differ from the previous built version, including parent directories for additions/deletions; leave unchanged files alone. Account for coarse timestamp resolution and monitor timestamps rather than assuming a nanosecond write is sufficient. Exercise the installed Cabal/GHC path early with alternating equal-length edits and deliberately equal initial timestamps. If the chosen policy cannot pass, fix it or explicitly reject the unsupported environment; a receipt alone must not conceal a stale binary.

Extend `Execution`, `parseExecution` and `manifestRunOptions` in `src/Test/Heni/Manifest.hs`, the manifest schema, and CLI corpus tests with this shape:

```json
{"execution":{"workers":4,"buildReuse":{"provider":"cabal","toolchain":"declared-cabal-ghc-environment-v1"}}}
```

Omission or null disables build reuse. Reject unknown provider names, extra keys, missing or blank toolchain identities, and wrong types. `baselineReuse` remains independently responsible for caching baseline test results. Report provider name, contract version, declared toolchain, trust kind `trusted-tool`, input identity, worker/generation identity, cold initialization versus incremental build versus verified skip, and retirement reason. Preserve redaction and report decoding compatibility; extend `src/Test/Heni/Report.hs` and report schema only where required by their actual codec boundaries. Successful CLI decoding and execution, receipt refusal, and the existing custom-provider rejection tests complete this milestone.

### Milestone 4: Prove native parity and document the contract


Add `examples/cabal-reuse/` with a small Cabal project and a selector-aware test executable, derived from `examples/minimal/`. Include a caught mutation, a survivor, unexpected compile failure, explicitly expected build rejection, stale edit, and control; use at least three distinct selectors and alternate equal-length edits. Add `scripts/test-cabal-reuse.py` to generate fresh and reused manifests, run the built Heni executable with one and multiple workers, and compare every selected case's verdict and run confidence. Wire it into an appropriate integration test/check path and include fixture files in source archives.

The fixture must count cold local builds from worker initialization/build-directory observations and retain logs; do not infer them from elapsed time or equate every Cabal invocation with a cold build. Run a campaign longer than its worker count and prove at most W cold initializations, distinct worker roots, selector baseline execution, and unchanged-source reuse. Include compile rejection and stale edits in that campaign so they cannot accidentally reset the build directory. Run failure-injection campaigns separately to prove retirement and receipt refusal; additional cold builds after retirement are expected and reported. Record timings and changed-file counts as observations, without machine-dependent speed thresholds.

Update `docs/user/build-reuse-guide.md`, `docs/user/manifest-reference.md`, `docs/user/scheduling.md`, `docs/user/reports.md`, and relevant capability documentation. Revise ADR 8 with the trust distinction and receipt/failure contract. Maintain existing OKF document metadata/log/index conventions when changing guides. Update the improvement request with the implemented plan and evidence once acceptance passes. At completion record outcomes and triage any implementation friction.

## Concrete Steps


Run all commands from the repository root. Use the existing project development environment with GHC, Cabal, Bun and Python available. No code implementation has been performed during creation of this plan.

```bash
cabal test heni:heni-workspace heni:heni-scheduler -j1 --test-show-details=direct
cabal test heni:heni-runner heni:heni-unit heni-cli:heni-cli-test -j1 --test-show-details=direct
python3 scripts/check-schemas.py
```

After creating the native fixture and its driver, run:

```bash
cabal build heni-cli:exe:heni
python3 scripts/test-cabal-reuse.py
cabal test all -j1 --test-show-details=direct
python3 scripts/check-docs.py
```

The new driver should locate Heni through `cabal list-bin heni-cli:exe:heni`, allocate fresh output directories and return zero only after asserting parity, cold counts, isolation and receipt refusal. Print a concise summary such as `Cabal reuse: parity, worker cold-build bounds, and receipt refusal passed`, plus the evidence directory. Campaigns containing a survivor legitimately have a nonzero Heni exit status; the driver must inspect reports and compare expected verdicts rather than treating every nonzero subprocess exit as a harness failure. Existing Cabal test commands must report all selected suites passed, and schema/document checks must exit zero.

Before version-specific implementation decisions, discover sources with `mori registry search Cabal`, `mori registry show haskell/cabal --full`, and `mori registry docs haskell/cabal`; inspect `cabal --numeric-version` and `ghc --numeric-version`. Verify proposed compatibility bounds against authoritative Hackage versions and upstream release tags. Never search or read `/nix/store`.

## Validation and Acceptance


Milestone tests must demonstrate behavior, not merely constructor shape. Restoration tests check unchanged-file preservation, additions, deletions, modes, path-type transitions and unexpected-state rejection. Scheduler tests check correct baseline selection, source transitions, resource contracts, redaction, skipped-build provenance, and retirement before reuse. Keep old custom-provider equal-mtime and failed-build verification tests passing.

The native campaign is the central acceptance artifact: every fresh verdict equals its reused counterpart; caught mutations remain caught, survivors remain survivors, compile failures retain their specific classification, and stale edits remain invalid edits. A missing/mismatched successful receipt is always infrastructure failure before tests, never detection. Verify current-run tokens as well as input identities, including a stale receipt for identical input bytes. Build failure and timeout never produce success receipts. Re-run a case after an injected retirement to show it starts from a clean worker generation.

For one stable contract and no infrastructure faults, N cases with multiple selectors on W workers have no more than W cold local builds. Incremental builds when returning to baseline are permitted and counted separately. Genuine contract changes and injected infrastructure failures are outside that bound but must expose retirement and subsequent cold initialization. A retained candidate failure alone must not break the healthy-campaign bound. Do not claim general Cabal/GHC compatibility from a mock receipt test: record actual versions and native evidence, including coarse-time edits, in this plan and the user guide.

## Idempotence and Recovery


Workspaces and receipts are temporary, private to one worker and one campaign. Never delete the user's source build directories. Repeated verification runs use new output paths because `runCampaign` rejects existing run directories. On failed reset, invalid receipt, unsafe path, cleanup failure or cancellation, discard the owned generation and its success marker; do not repair it by trusting old receipts. Preserve failure evidence in the report. Incomplete reports remain read-only evidence, not permission to resume commands. Restore normal execution by omitting `execution.buildReuse`; no persistent cache migration is required.

## Interfaces and Dependencies


The public opt-in constructor belongs to `Test.Heni.BuildReuse.Cabal`; shared lifecycle and worker contracts belong to `Test.Heni.BuildReuse` and `Test.Heni.Runner`. The manifest and Haskell API must select the same implementation. Preserve existing four-argument custom `BuildReuse` construction or document any unavoidable public API change with the project's version policy before release. Use an internal provider-kind dispatch for trusted Cabal outcomes rather than encoding behavior by matching arbitrary contract strings.

No new Cabal library dependency is needed: execute the declared external command through `Test.Heni.Process`. The provider must preserve argv, sensitive-argument redaction, time/output limits, cwd constraints and process-group cleanup. Any new runner-owned receipt-token environment variable must join `reservedEnvironment` and must not be overridable by a manifest. Keep baseline test result keys and built-input success state separate. Update exposed module and source-archive lists in `heni.cabal`, along with API consumers under `test/api/` when needed. This is a standalone follow-on to the existing reuse implementation, with no new MasterPlan dependency.
