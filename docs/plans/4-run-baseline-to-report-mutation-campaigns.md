---
id: 4
slug: run-baseline-to-report-mutation-campaigns
title: "Run baseline-to-report mutation campaigns"
kind: exec-plan
created_at: 2026-10-24T14:33:08Z
intention: "intention_01m5q57803ea88q9ts1vv62h4r"
master_plan: "docs/masterplans/1-bootstrap-heni-for-trustworthy-mutation-testing-and-hackage-release.md"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-24T14:33:08Z
  revisions:
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-24T15:26:19Z
      mode: "implement"
      note: "Integrate real baseline/candidate execution with portable reports, selected ledger, and journal recovery"
---

# Run baseline-to-report mutation campaigns


This ExecPlan is a living document. Maintain Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective. Record implementation friction with `agents/skills/exec-plan/record-friction.ts` under this plan. Follow `agents/skills/exec-plan/ADR.md` before ADR changes, and distill durable decisions before completion. All commands below run from the repository root unless stated otherwise. Paths named as new files are planned artifacts, not claims that they already exist.


## Purpose / Big Picture


A user can execute a real curated mutation from the Haskell library and obtain a durable explanation of whether the intended fault was caught. Baseline, edits, build/check, test, classification, and cleanup form one serial execution path. A cancelled or failed run still accounts for every selected case and keeps the evidence it managed to write.


## Progress


- [x] M1 (2026-10-24; real standalone Cabal guard/survivor/compile-error cycle passed): A real replacement case completes the unchanged-baseline-to-report path through public library calls.
- [x] M2 (2026-10-24; lifecycle, control, timeout, patch, baseline, cleanup and cancellation checks passed): Baselines, controls, stage rules, and all selected-case outcomes resist false attribution.
- [x] M3 (2026-10-24; report round trip/move, strict token decoding, journal recovery and write-failure checks passed): Incremental evidence and atomic summaries remain inspectable after failure or interruption.


## Surprises & Discoveries


Aeson normally discards duplicate object keys during map conversion. The shared decoder now checks its original token stream, including escaped-equivalent keys, before constructing values. Integration also showed that normal cancellation must retain Cancelled evidence without being relabeled as an infrastructure failure solely because the caller requested interruption.


## Decision Log


2026-10-24: Journal sequenced complete ledger snapshots after observations, then atomically rename the final report. Recovery is read-only and explicitly untrustworthy; only an unfinished end-of-input suffix is tolerated.

2026-10-24: Keep exact witnesses separate from capped raw logs. Baselines and candidates use the same stage-evidence validator; hooks can enrich selection/replay but cannot replace actual outcomes or witnesses. Preserve primary and secondary finalizer exceptions so cleanup cannot swallow cancellation.

2026-10-24: Match existing maintainer metadata from mori://shinzui/keiro/packages/keiro-core and mori://shinzui/shibuya/packages/shibuya-core as requested: Nadeem Bitar, nadeem@gmail.com. The separately selected license remains BSD-3-Clause.


## Outcomes & Retrospective


The first real library campaign is accepted. `cabal run heni:exe:heni-library-example -- --output .heni-runs/library-smoke` produced caught, survived and unexpected-build-failure from actual Cabal builds/tests with unchanged source bytes. All four core test suites pass; the runner suite additionally exercises supervised Git patches, baseline and control failures, no named selection, wrong diagnostics, timeout, observer/cleanup/final-write failures, interrupted active/queued accounting, report redaction, moved directories, missing baseline logs, truncated final journal records and interior/semantic corruption. The emitted report passes the published Draft 2020-12 schema through jsonschema 4.26.0. Ownership/recovery decisions are distilled in docs/adr/5-campaign-ledger-and-report-trust.md. No friction met the recording threshold. Framework evidence, replay execution, scheduling and release-matrix proof remain with later owners.


## Context and Orientation


The hard prerequisites are `docs/plans/2-implement-isolated-snapshots-and-checked-mutations.md` and `docs/plans/3-supervise-bounded-processes-and-cancellation.md`, both Complete. Their acceptance includes the model from the first child. The working tree should now contain `Workspace.hs`, `Edit.hs`, `Process.hs`, and pure `classifyCase`/`summarizeRun`. There is no CLI prerequisite. Read `docs/initial-spec.md` sections 5, 7, and 10 and the two research records indexed by `docs/research/index.md`.

A run ledger is the full ordered selected-case list and its current states; it is the source for exactly one final record per selected ID. A journal is an append-only sequence of completed observations that survives before final report writing. Atomic finalization means write a complete new summary and rename it into place, rather than allowing readers to see a half-written JSON document. It does not promise durability against arbitrary storage or power failures.

The prerequisites establish [public boundaries](../adr/1-framework-neutral-core.md), [classification](../adr/2-evidence-owned-classification.md), [workspaces](../adr/3-immutable-snapshots-and-staged-edits.md) and [process ownership](../adr/4-posix-process-ownership.md). The relevant external boundary is [library-owned behavior](mori://shinzui/keiro/okf/adrs/concepts/ADR-28): the runner and classifier remain reusable without CLI exits or mandatory terminal output.


## Plan of Work


### M1: The first real cycle


Implement `src/Test/Heni/Runner.hs`, the public `runCampaign`, and a minimal `src/Test/Heni/Report.hs`. Create `examples/minimal/` with a standalone Cabal fixture having a small capacity guard and a focused test that prints a stable diagnostic only for its intended assertion. Supply an executable library example under `examples/library/` as `heni-library-example`. It must snapshot the fixture, build/test the baseline, apply one checked guard replacement, build/test the candidate, classify evidence, persist a report, and discard the workspace. Add a deliberately surviving edit and an unrelated compile error as negative controls for attribution.

Before broadening variants, run this path through the real workspace and process implementations, including Git patch commands through the supervisor. No fake test runner or mocked process result may satisfy M1. Check the original fixture's bytes after the run. Initial report output can be small, but it must already preserve real case ID, commands, stage outcomes, and diagnostic evidence. Baseline selection and candidate selection must be identical. Keep case execution serial and fresh-copy isolation until the later scheduling plan proves reuse.

### M2: Lifecycle and validity gates


Preflight the entire selected campaign, prepare its ledger, and validate configuration before mutating anything. Run an unchanged baseline for each necessary configuration/selection without reuse initially. Abort affected candidates when baseline build/test or discovery fails and mark them not-run with the baseline reference. A nonempty named selection must be both discovered and executed. Generic diagnostic mode has explicitly weaker evidence and no fabricated test counts. Failed controls make the run fail even if all mutants were caught.

For each candidate, restore pristine bytes by creating a fresh workspace, apply the ordered edits, verify changes, run build/check, and run tests only when the expectation requires them and preceding stages succeeded. An intentional build-rejection still requires its unchanged baseline check to succeed. An unexpected build failure never counts as a semantic kill. Feed all evidence through the pure classifier. Record hooks and lifecycle errors without losing the primary failure. Validate custom hooks through the same baseline/change/timeout/cleanup gates; they cannot synthesize a successful run bypass.

Cancellation stops new work, terminates owned children using the supervisor, finalizes the current case with its observed outcome and interruption reason, and fills queued IDs as not-run. Since the spec has no separate cancelled case verdict, use not-run with an explicit cancellation reason for interrupted work without a completed verdict; preserve any completed stage evidence. A cleanup failure is infrastructure-error and invalidates the overall run even after a fault was observed. Do not turn cancelled work into timeout unless a budget actually expired.

### M3: Durable reports and events


Own `schemas/report-v1.schema.json`, report codecs, run progress events, and journal recovery. Allocate output directories exclusively; refuse to merge into an existing run. Write the selected-ID ledger before starting cases. Append structured stage/case completion records, preserve per-case logs and diffs, then atomically replace the final report. Store schema/tool version, snapshot/policy, effective settings, selected IDs, descriptions, stage durations, commands, detection kinds, counts when known, replay slots, resource metadata slots, and relative evidence paths. Exclude inherited secrets and redact explicitly sensitive command/environment values. Record the redaction so the report never implies a fully reproducible secret value was included.

Provide library `readReport` and `recoverReport` operations that can reconstruct a clearly incomplete report from a journal, tolerate only a final truncated journal record, reject interior corruption, and never resume commands implicitly. Validate evidence path containment before opening report references. Move a report directory and demonstrate it still renders with its artifacts. Report loss or disk-full failure returns infrastructure error in memory and best-effort stderr only at the future CLI boundary; do not guarantee disk writes when the filesystem refuses them. Preserve the original and cleanup/report errors together.

Expose a progress callback whose exceptions cause controlled termination and an untrustworthy run, not silent success. Keep its invocation outside critical ownership transitions. Document that arbitrary uncooperative Haskell hooks are trusted code and cannot be made safely preemptible by a type signature alone. Record the evidence lifecycle and recovery limitations in `docs/user/reports.md` and a local ADR.


## Concrete Steps


After introducing the fixture and targets, run from the repository root:

```bash
cabal test heni:heni-runner --test-show-details=direct
cabal run heni:exe:heni-library-example -- --output .heni-runs/library-smoke
cabal test heni:heni-unit heni:heni-workspace heni:heni-process --test-show-details=direct
```

Use a new output directory for each manual run. The example should show or return one caught diagnostic case, one survived case, and one unexpected-build-failure case with source bytes unchanged. Tests assert values, not unstable timestamps. Add `test/runner/` and declare fixture source/data files in `heni.cabal` so they later survive source distribution.


## Validation and Acceptance


M1 must use actual subprocess compilation and assertion failure in a disposable copy. Then the integration suite injects failing baseline, failed/timed-out control, invalid edit, absent selection, wrong diagnostic, test timeout, launch failure, and cleanup failure. Each produces the specified distinct case/run evidence. Verify stage skipping with a sentinel that would be created if an inappropriate test command ran. Every selected ID appears exactly once, including queued work after cancellation. No source or evidence path escapes its owned directory.

Interrupt during baseline, mutation, test, and report finalization. A graceful interruption returns/reconstructs a partial report; a killed runner leaves the journal recoverable to an explicitly incomplete ledger. Recovery must never claim missing work was caught. Test a truncated last record, interior corruption, missing log, unwritable output, and moved report directory. Compare CLI-independent run status with the pure summary policy: any infrastructure failure outranks ordinary contract failure; an incomplete score cannot pass. Confirm report schemas and codecs agree on all emitted fixtures, including absent counts and redactions.


## Idempotence and Recovery


Reruns create fresh output/workspace directories. Recovery is read-only reconstruction and does not rerun cases or overwrite old evidence. If interrupted while finalizing, retain both the last complete summary and the journal needed to diagnose it; a recovery operation writes a separate recovered artifact unless explicitly replacing a known temporary file. Existing run directories are never treated as permission to delete data. Preserve user work and invalidate failed workers.


## Interfaces and Dependencies


Hard prerequisites: `docs/plans/2-implement-isolated-snapshots-and-checked-mutations.md` and `docs/plans/3-supervise-bounded-processes-and-cancellation.md`. This plan owns `runCampaign`, lifecycle events, `RunResult`, report codecs/schema, and journaling; the model owner retains classification authority. The intended shape is `RunOptions -> Campaign -> IO RunResult`, with validated campaign construction and explicit progress/error contracts.

`docs/plans/5-expose-strict-manifests-and-the-shared-cli.md` lowers portable input into this runner and renders its status. `docs/plans/6-add-named-test-adapters-replay-and-crash-evidence.md` fills adapter/replay observations. `docs/plans/7-add-resource-aware-workers-and-verified-reuse.md` replaces serial scheduling while preserving this lifecycle. Lookup JSON/hash dependencies through Mori and verify releases before bounds; no mandatory terminal or framework dependency may enter the core.
