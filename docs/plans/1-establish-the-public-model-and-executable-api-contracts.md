---
id: 1
slug: establish-the-public-model-and-executable-api-contracts
title: "Establish the public model and executable API contracts"
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
      at: 2026-10-24T15:01:22Z
      mode: "implement"
      note: "Implement public model, classification truth table, API consumers, and ordinary Cabal validation"
---

# Establish the public model and executable API contracts


This ExecPlan is a living document. Maintain Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective. Record implementation friction with `agents/skills/exec-plan/record-friction.ts` under this plan. Follow `agents/skills/exec-plan/ADR.md` before ADR changes, and distill durable decisions before completion. All commands below run from the repository root unless stated otherwise. Paths named as new files are planned artifacts, not claims that they already exist.


## Purpose / Big Picture


A library user can construct a deliberate mutation case and inspect why supplied execution evidence does or does not prove detection. This first slice produces a buildable Cabal library, a compact API usage fixture, and executable classification rules. It does not claim to execute a real mutation yet. Its purpose is to make the difficult semantics testable before filesystem, subprocess, or framework implementation can hide mistakes.


## Progress


- [x] M1 (2026-10-24; `cabal build heni:lib:heni` and exposed-only consumer compilation passed): Ordinary Cabal builds the library and a small public-API consumer with the adopted Haskell conventions.
- [x] M2 (2026-10-24; 28 adversarial classifier scenarios plus ledger invariants passed): A pure classifier rejects false detections and accounts for every defined outcome.
- [x] M3 (2026-10-24; four public construction trials and consumer label regression compile): Four representative case definitions compile through the public API, with documented ownership and extension contracts.


## Surprises & Discoveries


The source corpus had containers 0.7 while Hackage and upstream tags report 0.8.1. Bounds admit both; initial execution uses the installed 0.7 and final bound testing remains in EP-9.


## Decision Log


2026-10-24: Keep a single pure classifier with explicit validity precedence and a selected-ID ledger that rejects duplicates and fills missing results. Record framework neutrality and classifier ownership in [the boundary ADR](../adr/1-framework-neutral-core.md) and [the evidence ADR](../adr/2-evidence-owned-classification.md).

2026-10-24: The maintainer selected BSD-3-Clause in this session; LICENSE and package metadata use that choice.


## Outcomes & Retrospective


The core builds with GHC 9.12.4 and ordinary Cabal. `cabal test heni:heni-unit --test-show-details=direct` passes 28 classification scenarios plus API/label and ledger invariants; `cabal haddock heni` builds the initial API reference. Every required outcome has a counterexample fixture, including exact named attribution, timeouts, replay identity, control and baseline failures. Real mutation execution is deliberately deferred to the next owners; no fake runCampaign is exported. No implementation friction met the recording threshold. The two local ADRs distill package boundaries and evidence trust.


## Context and Orientation


The repository has `README.md`, `docs/initial-spec.md`, and the research bundle indexed by `docs/research/index.md`; it has no Cabal package or Haskell source at plan creation. `docs/research/mutation-testing-survey.md` describes replacement, patch-catalogue, generated-code, and external-diagnostic patterns. `docs/research/ecosystem-mutation-testing-design.md` records ecosystem comparisons and adoption choices. Read both before drafting types. The existing `nix/haskell.nix` expects the root package `heni` and names GHC 9.12.4; it is not evidence of a supported release matrix.

A case is a stable ID, fault explanation, ordered edits, commands, selection, expectation, and budgets. A baseline is the same configuration without edits. A control explicitly changes no bytes and must pass. Evidence is what a stage actually observed, distinct from what a caller expected. A verdict is the classifier's conclusion from those observations. A campaign is one selected collection of cases and its baselines/controls.

No local ADR existed at creation. The inspected cross-repository decisions [consumer-owned effects](mori://shinzui/mori-app/okf/adrs/concepts/ADR-1) and [library-owned behavior behind CLI commands](mori://shinzui/keiro/okf/adrs/concepts/ADR-28) support plain IO hooks and one classifier. Their service dependencies are not requirements. Adopt [core standards](mori://shinzui/haskell-jitsurei/docs/core-standards), [record patterns](mori://shinzui/haskell-jitsurei/docs/core-record-patterns), and [prelude guidance](mori://shinzui/haskell-jitsurei/docs/core-custom-prelude) with the public orphan-instance boundary described below.


## Plan of Work


### M1: Buildable package and consumer


Create root `heni.cabal`, `cabal.project`, `src/Test/Heni.hs`, and a test suite `heni-unit` under `test/unit/`. Keep the root layout compatible with the existing optional Nix scaffold. Add a plain Cabal CI job in `.github/workflows/ci.yml`. Use GHC2024, a common stanza with DeriveAnyClass, DuplicateRecordFields, OverloadedLabels, and OverloadedStrings, strict record fields, explicit deriving strategies, and postpositive qualified imports. Keep project convenience exports in `Test.Heni.Internal.Prelude`, not the public umbrella. Constructor matching is permitted by the record guidance; use it and explicit combinators throughout the public import closure so `Data.Generics.Labels` cannot impose orphan instances on downstream DSL users. Record this scoped adaptation in the local architecture decision.

Choose the initial compiler within the GHC 9.12-or-newer policy only after checking available releases and the toolchain. Use Mori to inspect dependencies, then Hackage and upstream tags before recording bounds. Begin with the minimum necessary base/text/containers-style dependencies; do not introduce a typeclass hierarchy, an application effect stack, framework dependencies, or a broad lens API. Add license metadata only after the maintainer selects a license; do not fabricate identity or licensing to satisfy packaging early. M1 is accepted when a separate test consumer imports only exposed modules and builds with ordinary Cabal.

### M2: Evidence and classification


Define `CaseId`, `CommandId`, `RelativeTarget`, positive `StageBudget`, `Stage`, `ProcessOutcome`, `SelectionEvidence`, `StageEvidence`, `Expectation`, `CaseResult`, and `RunResult` in `src/Test/Heni/{Case,Command,Expectation,Result,Internal/Model}.hs`. Use smart constructors for constrained values and distinguish missing counts from known zero counts. Represent expected-build-rejection, named-test, generic-diagnostic, and crash-probe expectations as separate constructors, plus explicit control definitions. Replay policy is data now; execution arrives later. Semantic failures require a successful build, nonempty executed selection where named tests are required, and the matching witness. Generic diagnostics explicitly record their weaker evidence level and never invent test counts.

Implement pure `classifyCase` and `summarizeRun`. Preserve the spec's nine outcomes: caught, survived, invalid-mutation, uncovered, unexpected-build-failure, wrong-failure, timed-out, infrastructure-error, and not-run. Run-level baseline/control failures reference affected IDs rather than being disguised as mutant kills. Use a validated selected-ID collection so no case disappears or occurs twice. Model invalid configuration separately before execution. Store detection kind, reasons, stage evidence, original/replay outcomes, and secondary cleanup errors rather than forcing all facts into one label. The semantic score is caught semantic cases divided by caught plus survived semantic cases; expected build rejections, explicit crashes, controls, and reviewed exclusions are separate tallies. Invalid, uncovered, wrong-failure, timed-out, infrastructure, and unrun cases remain visible and prevent a complete passing gate. A zero denominator has no score. Named-test expectations default to the exact declared failure set; an additional undeclared assertion failure is wrong-failure, and a setup error remains infrastructure evidence even if the intended assertion also failed.

Define precedence explicitly in `docs/design/classification.md`: no detection without a valid changed mutation or explicit control; baseline failure prevents candidate execution; launch/report/cleanup failure makes the run untrustworthy; runner timeout cannot be overridden by matching output; missing named selection is uncovered; semantic build failure is unexpected-build-failure; mismatched failures and required replay mismatches are wrong-failure; passing valid semantic candidates survive. A known-empty selector in preflight is a configuration/selection diagnostic; if discovered during execution it produces uncovered evidence. Keep cause ordering and secondary errors visible.

### M3: API construction trials


Add `test/api/Consumer.hs` and example definitions for the four RES-1 patterns. Prefer concrete constructors and a small sequence such as validate, run, inspect; do not introduce a fluent DSL solely to save a few lines. The executable test in this milestone feeds synthetic evidence into the classifier and clearly labels that fact. It must express precise diagnostic, named-test, build-rejection, replay, control, and crash requirements without framework types. Separate serializable `CaseDefinition` from `CaseHooks` containing custom IO edits/expectations. Custom expectations may return evidence or a structured rejection, but cannot override baseline, timeout, workspace, or cleanup validity gates. Custom edit hooks receive checked workspace operations; they do not receive implicit authority to restore the active checkout.

Publish the proposed signatures and error semantics in `docs/design/api-contract.md`, with `runCampaign :: RunOptions -> Campaign -> IO RunResult` as the target runner shape, and a callback returning IO for progress. This milestone does not implement `runCampaign` with a fake successful runner. Record narrow contracts for workspace, process, report, and adapter owners. Create local ADRs for the framework-neutral package boundary and evidence-owned classifier following the ADR workflow. Update `docs/initial-spec.md` only where a prototype has resolved an open design detail; retain its requirements.


## Concrete Steps


Inspect the checked-in research and locate each contemplated dependency before using its API:

```bash
mori registry list
mori registry search text
mori registry show haskell/text --full
mori registry docs haskell/text
```

After creating the package and the `heni-unit` target, run:

```bash
cabal build heni:lib:heni
cabal test heni:heni-unit --test-show-details=direct
cabal haddock heni
```

The unit target includes public-consumer compilation and the classifier truth table. Add a separate downstream compile fixture that defines its own overloaded label instance and imports `Test.Heni`; it must continue to compile. If Cabal/GHC are absent, the existing `nix develop` shell is a local convenience, while CI must exercise ordinary Cabal. Do not search the Nix store. Record dependency registry/tag evidence and actual compiler output in `docs/design/compatibility.md`.


## Validation and Acceptance


The truth table must include a correct named failure, wrong named failure, correct diagnostic with wrong exit, a diagnostic printed before timeout, zero executed tests, skipped intended tests, semantic compile failure, intentional build rejection with matching and unrelated diagnostics, stale/no-op edits, failing baseline/control, setup failure, crash without its probe, and replay mismatch. Each must produce the specified distinct outcome and never an accidental caught result. Property checks show that duplicating/reordering evidence cannot inflate counts and that every selected case has one result. Test run summaries containing both a survivor and infrastructure failure; infrastructure must take precedence. A zero semantic denominator yields no score, not 100 percent.

The four API definitions compile without exposing test-framework types. The public import closure does not add an orphan label instance. A developer can find why a case was rejected without interpreting terminal text. Public constructors, defaults, and errors have initial Haddock. Passing these tests proves the model only; real execution remains an explicit later gate.


## Idempotence and Recovery


All edits are additive in this repository. Run tests repeatedly against temporary fixtures. Do not change consumer repositories or rewrite generated Nix pins. If a construction trial forces an incompatible type change, update the truth table, API contract, relevant ADR, and downstream child interface descriptions together before accepting this plan. Preserve unrelated working-tree edits.


## Interfaces and Dependencies


This plan has no hard prerequisites. It owns the root package and public model consumed by `docs/plans/2-implement-isolated-snapshots-and-checked-mutations.md` and `docs/plans/3-supervise-bounded-processes-and-cancellation.md`. `docs/plans/4-run-baseline-to-report-mutation-campaigns.md` implements the target runner signature. Export stable user-facing definitions from `Test.Heni`; keep platform details and unchecked constructors internal. Dependencies must be released, minimal, and looked up through Mori before API use. No concrete version range is chosen by this plan text. JSON encoding remains explicit work in the report/manifest owners, not derived compatibility by accident.
