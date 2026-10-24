---
id: 6
slug: add-named-test-adapters-replay-and-crash-evidence
title: "Add named-test adapters replay and crash evidence"
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
      at: 2026-10-24T16:04:59Z
      mode: "implement"
      note: "Implement attempt-bound evidence protocol, optional reporters, property replay and fresh crash probes"
---

# Add named-test adapters replay and crash evidence


This ExecPlan is a living document. Maintain Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective. Record implementation friction with `agents/skills/exec-plan/record-friction.ts` under this plan. Follow `agents/skills/exec-plan/ADR.md` before ADR changes, and distill durable decisions before completion. All commands below run from the repository root unless stated otherwise. Paths named as new files are planned artifacts, not claims that they already exist.


## Purpose / Big Picture


A maintainer can require a particular test to fail, reproduce a property counterexample, or explicitly probe a native crash without confusing setup failure or an unrelated assertion with a caught mutation. Optional Tasty and Hspec reporters provide stronger evidence while existing consumer suites remain in their own subprocesses.


## Progress


- [x] (2026-10-24) M1: A versioned test-evidence protocol proves discovery, execution, and named failure in real subprocess fixtures.
- [x] (2026-10-24) M2: Optional Tasty and Hspec reporters provide the same evidence through existing suites.
- [x] (2026-10-24) M3: Property replay and declared crash probes preserve original/replay observations and reject wrong detections.


## Surprises & Discoveries

2026-10-24: Tasty exposes exact selected tree/status order, while the stable Hspec
formatter reports completed selected IDs but cannot independently enumerate all
unfiltered examples. Both reporters explicitly preserve unknown discovery;
identity and execution checks use the exact selected IDs. Hspec partial
fail-fast completion is rejected by comparing its expected count.

2026-10-24: QuickCheck supplies a native seed/size replay token. The initial
helper supports one explicitly selected replay property per attempt, recording
version and generator arguments; other native formats use the typed builder.



## Decision Log


2026-10-24: Keep the dedicated attempt-bound channel authoritative. Typed
observers may reject strong protocol facts but cannot overwrite them. A reporter
exception after completion appends invalidation instead of deleting evidence.
See [ADR 7](../adr/7-attempt-bound-test-evidence.md).

2026-10-24: Use dedicated reporters during Heni attempts, retaining native
filters/options and ordinary direct execution outside Heni. Hspec history
reruns are rejected because they can change an attempt's selected set.


## Outcomes & Retrospective


Accepted on macOS/GHC 9.12.4. The standalone producer suite passed actual
baseline/candidate/replay supervision with intended/wrong/skipped/setup,
stale/partial/count/version rejection, zero selection, opaque token mismatch,
replay timeout and post-completion invalidation. Fresh signal probes passed
only with the expected native signal; stale/missing/wrong-signal/numeric-exit
and timeout negatives were preserved.

Both optional package tests passed ordinary direct framework execution, exact
named failure, wrong assertion, setup exception, empty selection, combined
native/Heni filters and CLI manifest parity. Hspec additionally passed pending
selection, dry-run rejection, real QuickCheck reproduction and an invalid
native replay token. Core unit/workspace/process/runner/CLI regression suites
passed serially. The emitted evidence and report schema checks and shared
manifest corpus passed. Source/registry compatibility is recorded in
`docs/design/compatibility.md`; ADR 7 records the durable contract.

The first broad concurrent build/test run exceeded a process fixture's short
startup budget; the same suite passed with serial Cabal test jobs, now explicit
in CI. Linux execution remains part of the final release matrix gate in
`docs/plans/9-validate-portable-packages-and-prepare-the-hackage-release.md`.
There was no external-surface friction to triage for this child. Known limits
are unknown unfiltered discovery, one replay property per attempt, and no
Hspec history/dry-run execution inside an evidence attempt.


## Context and Orientation


Begin only after `docs/plans/4-run-baseline-to-report-mutation-campaigns.md` is Complete. Its serial runner already performs baselines, edits, supervised stages, classification, and reports. `docs/plans/5-expose-strict-manifests-and-the-shared-cli.md` is a soft dependency: this plan can prove library behavior independently and must later coordinate portable syntax with that schema owner. Read spec sections 7–8 and research RES-1/RES-2 through `docs/research/index.md`.

A test adapter converts framework events into Heni evidence. A reporter is code installed in the consumer's test executable to emit those events. Replay reruns the recorded generator configuration and counterexample token to check the same named failure. A crash probe is a case-specific observation that the intended native operation was reached before the declared signal. None of these artifacts is a security attestation against a malicious test binary.

No local ADR existed at creation. Read and link prerequisite decisions on the model, execution, and evidence lifecycle; this plan adds a durable protocol and replay decision. Follow the framework-neutral public boundary: the generic package must not require either framework to build or run its core tests.


## Plan of Work


### M1: Structured evidence protocol


Implement `src/Test/Heni/Adapter.hs`, protocol codecs, `schemas/test-evidence-v1.schema.json`, and `test/adapter/`. Use a dedicated JSON Lines file or channel, separate from normal stdout/stderr. Records carry protocol version, run/case/stage attempt identity, stable full test ID, event sequence, and event kind. A final completion record reports discovered/selected/executed/passed/failed/skipped counts and named failures, allowing the core to cross-check totals and membership. Setup errors and incomplete execution are distinct from assertion failures. Discovery and execution must agree on the intended identity; duplicate display names require unambiguous IDs or a validation failure.

Allocate the evidence destination fresh per attempt and pass its identity explicitly. Reject stale files, wrong run IDs, duplicate/conflicting completion, unsupported versions, impossible counts, unexpected test identities, interior corruption, and a missing final record. Delete no prior evidence to make a malformed run look clean. A named expectation needs its intended test executed and failed, with the actual failure set matching the explicitly allowed named failures and no setup errors; merely seeing the name in a discovery list or stdout is insufficient. Preserve the exact mismatch as wrong-failure, uncovered, or infrastructure evidence according to the classifier contract. A protocol failure cannot downgrade silently to generic-diagnostic mode.

Before framework integrations, use a tiny standalone producer fixture through the actual supervisor and runner. Prove baseline pass, intended assertion failure, setup failure, zero selection, and stale evidence rejection. The adapter converts observations only; it cannot select the final mutation verdict.

### M2: Optional framework reporters


Create optional packages `adapters/heni-tasty/` and `adapters/heni-hspec/`, with exposed modules `Test.Heni.Tasty` and `Test.Heni.Hspec`, runnable fixtures, and their own test suites. Query Mori for each framework and read its supported reporter/formatter/ingredient APIs; if an exact framework is absent in the corpus, record that and consult upstream source/docs rather than guessing. Check Hackage and upstream tags before declaring version ranges. Do not scrape ordinary colored terminal output as a stable named-test protocol.

Give a consumer a small documented change to install the reporter, preserve their framework's existing filtering/options, and emit selection/execution evidence. Resolve stable IDs for nested and parameterized tests; when a framework cannot preserve identity under a mutation, fail with an explicit mismatch. Use subprocess isolation for the consumer executable; Heni does not become an in-process test framework. Package tests include an existing-style suite with the reporter and verify that normal direct execution still works. Keep these packages optional in installation and the core's dependency closure, but run their compatibility fixtures in repository release CI.

### M3: Replay and crash-specific evidence


Implement `src/Test/Heni/Replay.hs` and `Crash.hs` and corresponding runner hooks. For property cases preserve generator seed/token, size/configuration, framework version, and the original counterexample or a redacted artifact reference. A required replay must run with the same edited snapshot and intended test identity through the supervisor. A different failure, missing failure, replay timeout, or invalid token never counts as caught; preserve original and replay evidence and classify required replay mismatch as wrong-failure, with infrastructure/timeout reasons retained and run trust handled consistently. Prove one real property integration using a released QuickCheck or Hedgehog adapter supported by the chosen framework, rather than inventing a universal token grammar. Consumers can supply a typed replay builder for other frameworks.

A crash case must declare an allowed signal and a probe bound to this case/stage attempt. Ignore a stale marker from the baseline or another case. Require a matching native signal, a fresh probe, and no runner-enforced timeout/cancellation. Test a harmless fixture that writes the probe then raises the declared signal, plus wrong signal, no probe, stale probe, and timeout after probe. The probe is evidence of reachability, not proof of the root cause of an arbitrary native failure; document that limit. Generic crashes remain wrong-failure.

Update schemas and CLI examples with the manifest owner if that plan is complete; otherwise record exact pending lowering contracts in `docs/design/adapters.md` for the integration gate. Add a local ADR for evidence identity, completeness, replay, and probe semantics.


## Concrete Steps


Use Mori before depending on framework APIs:

```bash
mori registry search tasty
mori registry show UnkindPartition/tasty --full
mori registry docs UnkindPartition/tasty
mori registry search hspec
mori registry search QuickCheck
mori registry search hedgehog
cabal test heni:heni-adapter --test-show-details=direct
cabal test heni-tasty:heni-tasty-test heni-hspec:heni-hspec-test --test-show-details=direct
```

The targets above are created here. Add real named-test, property-replay, and crash fixtures under `examples/adapters/` and include them in source archives. The core tests use the standalone protocol fixture and do not require framework packages; optional-package tests exercise the frameworks.


## Validation and Acceptance


Both framework fixtures must prove an unchanged selected test passes, the exact intended test fails under mutation, and a different failed test produces wrong-failure. Zero selected or only-skipped intended tests cannot count as detection. A stale or malformed evidence artifact cannot be accepted even if the process exits 1. Protocol and count errors must be actionable. A partial test run with a visible intended failure but no trustworthy completion must not be promoted to a complete successful case.

A real property counterexample replays as the same named failure; intentionally changing its token/configuration or failing a different test prevents caught. The original evidence is never overwritten by replay. The explicit signal fixture is caught only with its fresh probe and expected signal; a numeric shell exit alone does not prove a crash. Run platform-sensitive tests on Linux and macOS. If CLI integration exists, compare the same cases through manifests; otherwise leave that reconciliation explicitly required by the migration plan.


## Idempotence and Recovery


Evidence and replay destinations are unique per attempt and never reused as proof for another run. Replay has its own timeout/output limits and cleanup, but retains original logs. Keep fixtures harmless and confined; do not use real broker/native corruption tests in the core suite. Unsupported framework versions fail compatibility checks instead of silently changing parsing behavior.


## Interfaces and Dependencies


Hard prerequisite: `docs/plans/4-run-baseline-to-report-mutation-campaigns.md`; soft dependency: `docs/plans/5-expose-strict-manifests-and-the-shared-cli.md`. This plan owns evidence protocol, adapter normalization, replay builders, crash probes, and optional framework reporter packages. It extends `StageEvidence` with the model owner and the report codec with the report owner; the existing classifier retains final authority. The public core sees stable test IDs and evidence records, never Tasty/Hspec internal types.

`docs/plans/8-prove-representative-script-migration-and-usability.md` requires portable adapter/replay/crash forms to agree with library calls. The reporter packages add optional source-distribution and compatibility obligations to `docs/plans/9-validate-portable-packages-and-prepare-the-hackage-release.md`; verify all four intended package names at release time.
