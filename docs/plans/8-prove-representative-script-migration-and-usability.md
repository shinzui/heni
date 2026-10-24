---
id: 8
slug: prove-representative-script-migration-and-usability
title: "Prove representative script migration and usability"
kind: exec-plan
created_at: 2026-10-24T14:33:08Z
intention: "intention_01m5q57803ea88q9ts1vv62h4r"
master_plan: "docs/masterplans/1-bootstrap-heni-for-trustworthy-mutation-testing-and-hackage-release.md"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-24T14:33:08Z
---

# Prove representative script migration and usability


This ExecPlan is a living document. Maintain Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective. Record implementation friction with `agents/skills/exec-plan/record-friction.ts` under this plan. Follow `agents/skills/exec-plan/ADR.md` before ADR changes, and distill durable decisions before completion. All commands below run from the repository root unless stated otherwise. Paths named as new files are planned artifacts, not claims that they already exist.


## Purpose / Big Picture


A maintainer can replace representative bespoke mutation orchestration with Heni while retaining the intended fault and failure witness. Reproducible local trials show which code disappears, which remains consumer-owned, and where the API still needs work. The result is a migration guide and evidence of usefulness, not an unsupported promise that every script can be converted.


## Progress


- [ ] M1: The surveyed use-case inventory maps to runnable local Heni fixtures and explicit unsupported boundaries.
- [ ] M2: Library and CLI trials preserve intended detections and reject legacy false positives.
- [ ] M3: Measured authoring, diagnosis, orchestration, and runtime results support the final public API and migration guide.


## Surprises & Discoveries


None yet.


## Decision Log


No implementation decisions yet; the approach below is the initial proposed contract.


## Outcomes & Retrospective


To be filled during implementation, including acceptance evidence, remaining limits, and friction triage.


## Context and Orientation


Hard prerequisites are `docs/plans/5-expose-strict-manifests-and-the-shared-cli.md`, `docs/plans/6-add-named-test-adapters-replay-and-crash-evidence.md`, and `docs/plans/7-add-resource-aware-workers-and-verified-reuse.md`, all Complete. These provide strict manifests, the real runner, optional framework reporters, replay/crash evidence, resources, and workers. Read `docs/research/index.md`, then `docs/research/mutation-testing-survey.md` and `docs/research/ecosystem-mutation-testing-design.md`. RES-1 inspected historical source and reports, not newly executed mutation suites; do not present those reports as fresh parity evidence.

The four required trial families are a compact replacement runner, a patch catalogue, a generated-code mutation, and an external checker diagnostic. Additional difficult cases include property replay, deliberate build rejection, explicit crash probes, controls, and shared-resource setup. A parity record compares intended observable behavior before and after adopting Heni. It may legitimately show that Heni rejects a legacy false positive; preserving a flawed exit-only classifier is not required parity.

No local ADR existed at plan creation. Read and link the actual public API, evidence, protocol, and resource ADRs now present. This plan records durable migration exclusions or API changes revealed by trials. Source material is identified canonically in RES-1; use Mori to refresh relevant source identities before making new claims.


## Plan of Work


### M1: Coverage of real patterns


Create `examples/migrations/` with independently authored, redistributable fixtures named replacement, patch-catalogue, generated-code, and diagnostic-checker. For each, preserve a stable mutation ID, description, baseline expectation, edit, selected test/command, expected witness, and a deliberately surviving variant. Map it back to the surveyed pattern in `docs/migration-guide.md`; cite canonical Mori project/package URIs and project-relative source paths when artifact URIs are pending. Do not copy licensed/private code into release artifacts without a compatible license. Do not edit the source consumer repositories.

Refresh the surveyed scripts via Mori and make a capability inventory covering source/fixture edits, generated artifacts, native crash probes, replay, external tools, multi-stage commands, controls, patch sets, and service resources. For each pattern state supported directly, supported through a documented custom hook, or unsupported with a specific missing contract. Keep database-state fault injection distinct from source mutation. Live service migrations remain separate optional consumer work; simulate the resource lifecycle with local self-contained fixtures in mandatory tests.

The generated-code fixture must explicitly order source generation and mutation so the build cannot silently regenerate away the fault. Record whether the target is generator input or generated output and verify the final changed bytes at the stage that matters. The patch catalogue validates all selected IDs and stale patches without requiring the user's monorepo. The external checker case needs exact exit and diagnostic evidence, with its weaker test-count guarantees stated.

### M2: Before/after behavior


Add `test/migration/` and `heni-migration` as a test target that runs every fixture through both public Haskell definitions and portable manifests. Include a small fixture-specific legacy-style orchestration baseline only where it is needed to measure replacement; label it as an independently authored comparison harness, not a copy of a production runner. Every case must first pass unchanged. Compare the same source snapshot, commands, selection, budgets, and resource setup, then normalize only volatile fields in result comparison.

Inject a wrong named test, unrelated compile failure, zero selection, stale edit, test hang, failed setup, stale report, and broken teardown. Record intended detection parity plus improvements where Heni correctly rejects a false positive. Replay must reproduce the same failure; crash cases must reach the declared probe; controls must pass. Compare serial/fresh and parallel/reuse modes where applicable. If any real use-case gap belongs to the existing spec, fix the owning module/schema and update its plan/ADR before accepting this plan. Do not work around a missing library feature by adding another general-purpose mutation runner in the examples.

### M3: Usability and value evidence


Create `docs/migration-guide.md`, finish `docs/troubleshooting.md`, and write `docs/validation/migration-results.md` with source identities, test commands, outcomes, limitations, and measurement method. Measure consumer-owned runner scaffolding before/after separately from mutation definitions and diagnostics. Record time/actions to add one new case, diagnose one wrong failure, and reproduce one result. Automated or agent-authored trials are not human usability studies; identify the operator and avoid fabricating human timings. Record hardware/compiler, cold/warm conditions, build time versus runner overhead, repeat count, and variation.

The minimum usability gate is that each required pattern needs only a manifest or a short Haskell definition plus domain-specific code. Consumers should not manually copy/restore their checkout, start background process cleanup loops, or recalculate mutation verdicts. Provide a quickstart taking a new user from an unchanged passing fixture to one caught mutation and then one survivor. Keep exact examples runnable in CI and source archives. Review the final exposed module list, hook signatures, defaults, report fields, and optional package boundaries against all trials before declaring API v1 ready for packaging. Document future migration batches as recommendations with canonical ownership, not unexecuted claims of completion.


## Concrete Steps


Refresh sources through their canonical owners; for example:

```bash
mori registry show shinzui/rdkafka-hs --full
mori registry show shinzui/nagare --full
mori registry show shinzui/keiro --full
mori registry show shinzui/shibuya --full
cabal test heni:heni-migration --test-show-details=direct
cabal test all --test-show-details=direct
```

After creating the fixtures, demonstrate one command per family with unique output directories:

```bash
cabal run heni-cli:exe:heni -- run examples/migrations/replacement/heni.json --output .heni-runs/migration-replacement
cabal run heni-cli:exe:heni -- run examples/migrations/patch-catalogue/heni.json --output .heni-runs/migration-patches
cabal run heni-cli:exe:heni -- run examples/migrations/generated-code/heni.json --output .heni-runs/migration-generated
cabal run heni-cli:exe:heni -- run examples/migrations/diagnostic-checker/heni.json --output .heni-runs/migration-diagnostic
```

Default manifests select intended-caught cases; negative variants are selected explicitly by the test harness and expected to fail the run contract. The fixture suite must document any optional compiler or Git requirement without hiding missing capability behind success.


## Validation and Acceptance


Every required family executes through library and CLI with matching per-case meaning. A standalone consumer can install the reporter only when needed and retain its existing test framework. The generated mutation demonstrably reaches the compiled/tested artifact instead of being overwritten by generation. Each wrong-failure injection has an explained non-success outcome, every selected ID appears once, and source/resource cleanup invariants hold.

The value report includes reproducible counts and observations for all four families, plus the richer replay/crash/resource trials. It distinguishes historical survey facts from newly executed evidence and states unsupported patterns. At least one compact manifest-only case and one custom Haskell case require no consumer orchestration beyond domain-specific edits/resources. Runtime improvements are reported only if measured; correctness and reduced duplicated lifecycle code are independent acceptance requirements. The combined suite reconciles all manifest, adapter, resource, and report fields before release preparation.


## Idempotence and Recovery


Run local fixture trials in fresh workspaces and output directories. Do not migrate or delete actual consumer scripts in this plan. Preserve failed runs as diagnostic evidence; compare against a freshly created fixture rather than restoring backups over a source checkout. Update the relevant owner plan when a trial exposes a defect, retaining the new regression check. Reclassify a newly discovered capability outside the initial spec as a proposed follow-up, not an implicit expansion of this plan.


## Interfaces and Dependencies


All three hard prerequisites must be Complete. This plan owns examples, migration/diagnosis documentation, and the parity/effort record. It integrates the public API, manifest schema, test protocol, resources, and report schema without becoming a second owner of their implementations. Dependencies on surveyed projects remain research inputs, not build dependencies. `docs/plans/9-validate-portable-packages-and-prepare-the-hackage-release.md` consumes these accepted examples and API decisions. Actual fleet migration remains future work with explicit consumer ownership and live-environment acceptance.
