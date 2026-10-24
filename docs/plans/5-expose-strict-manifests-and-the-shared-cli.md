---
id: 5
slug: expose-strict-manifests-and-the-shared-cli
title: "Expose strict manifests and the shared CLI"
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
      at: 2026-10-24T15:51:18Z
      mode: "implement"
      note: "Implement strict JSON lowering, shared-library CLI commands, portable schemas, and parity checks"
---

# Expose strict manifests and the shared CLI


This ExecPlan is a living document. Maintain Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective. Record implementation friction with `agents/skills/exec-plan/record-friction.ts` under this plan. Follow `agents/skills/exec-plan/ADR.md` before ADR changes, and distill durable decisions before completion. All commands below run from the repository root unless stated otherwise. Paths named as new files are planned artifacts, not claims that they already exist.


## Purpose / Big Picture


Shell, Python, and CI callers can define a mutation in versioned JSON and use `heni check`, `list`, `run`, and `report`. The CLI exposes the library's behavior and evidence without forcing callers to write Haskell or parse terminal output.


## Progress


- [x] M1 (2026-10-24; strict token/field/reference/default validation and shared schema corpus pass): Strict versioned manifests lower into the library model with actionable diagnostics.
- [x] M2 (2026-10-24; check/list/run/report, exits, clean JSON and real SIGINT finalization pass): CLI commands execute and render the shared library behavior with predictable exits.
- [x] M3 (2026-10-24; library/CLI stage/verdict parity, moved reports and real Cabal guard case pass): Library/CLI parity, schema agreement, and noninteractive use pass end-to-end checks.


## Surprises & Discoveries


The input boundary must distinguish missing fields from explicit nulls: Aeson optional-field defaults otherwise accept null silently. Shared corpus fixtures now assert the intended schema/decoder behavior. JSON Schema alone cannot detect duplicate keys or validate cross-command references, so the decoder retains those semantic checks.


## Decision Log


2026-10-24: Keep a small argument parser and rendering in heni-cli; the core library owns manifest lowering and isolated applicability checks. Source paths are manifest-relative; explicit CLI output paths are caller-relative by deliberate documented convention.

2026-10-24: Until the corresponding owners implement them, reject portable named/replay/attempt-bound crash and resource options clearly. Do not silently accept unexecuted features. The v1 schemas remain pre-publication contracts coordinated with later owners.


## Outcomes & Retrospective


`cabal test heni-cli:heni-cli-test --test-show-details=direct` passes the shared manifest corpus, library/CLI verdict and stage-decision parity, caught/survivor/empty-selection exits, clean redirected JSON/human output, no command execution during check/list, moved report/recovery rendering and a real POSIX SIGINT returning 130 with a complete interrupted ledger. `heni check examples/minimal/heni.json` reports all three edits applicable without tests, and the real CLI guard-bypass run passes with its precise diagnostic. The Python Draft 2020-12 validator accepts both schemas, the shared corpus and real emitted report. Docs/cli.md and docs/troubleshooting.md describe implemented behavior and every outcome. Wire/CLI decisions are distilled in docs/adr/6-explicit-portable-wire-boundaries.md. No friction met the recording threshold.


## Context and Orientation


Begin after `docs/plans/4-run-baseline-to-report-mutation-campaigns.md` is Complete. It provides the real serial runner, `examples/minimal/`, report schema/codecs, and journal recovery. Read `docs/initial-spec.md` section 9 and both research records. The proposed JSON example in the initial spec is illustrative; this work must make checked runnable examples, not quietly treat that sketch as a complete decoder.

A manifest is a portable case collection with schemaVersion, named command definitions, edits, selection, expectations, budgets, and policies. Lowering means validating that description into the same internal campaign the Haskell API uses. Built-in portable features must have a library equivalent; arbitrary Haskell functions cannot be serialized. No local ADR existed at plan creation; read and link the actual local boundary/report ADRs from prerequisites. [The inspected CLI ownership ADR](mori://shinzui/keiro/okf/adrs/concepts/ADR-28) supports a single behavioral implementation, not extra operational approval flows.


## Plan of Work


### M1: Strict input boundary


Implement `src/Test/Heni/Manifest.hs`, `schemas/manifest-v1.schema.json`, and public decoding/validation functions returning field- and case-specific errors. Keep JSON support in the library so embedding callers can use the exact portable contract. Use explicit stable keys/tags, reject unsupported versions and unknown keys at every object level, reject duplicate case IDs and unknown command references, and detect duplicate JSON object keys rather than accepting a last-key-wins ambiguity. Validate positive finite budgets, nonempty selections where required, exact match counts, and safe relative paths. Separate static validation from applicability checks and test discovery that requires command execution.

Make defaults explicit in the schema, effective in decoding, and emitted in reports. Resolve paths relative to the manifest location and declared source root, never an accidental current directory. Portable built-ins include diagnostic and build-rejection expectations now, with named-test/replay/crash protocol forms reserved only if they can be rejected clearly until implemented. Do not advertise an accepted feature that silently does nothing. Resource/setup command forms must invoke the shared supervisor and resource lifecycle when that owner lands; arbitrary named plugin strings cannot execute unknown Haskell hooks.

### M2: Thin command application


Create `heni-cli/heni-cli.cabal`, `heni-cli/app/Main.hs`, command modules, and `heni-cli/test/`; add the package to `cabal.project`. Command parsing and terminal dependencies stay here. `check` validates structure, command availability, and edits in a disposable copy, but does not run mutation tests or pretend it proved test discovery. Display which checks were performed. `list` returns IDs, tags, selectors, and expectations without running commands. `run` selects by case/tag, refuses unknown case IDs, fails empty selection by default, and records the exact selected set and selection rule. If an explicit allow-empty option is provided, report the no-work run honestly without a semantic score. Define repeated filters as union within each filter kind and intersection across kinds; record this in help and tests.

`run` calls the library runner. `report` uses stored reports or an explicit journal-recovery option and never reruns a process. Human output shows counts, incomplete cases, witnesses, and artifact locations. Machine-readable output remains clean JSON with progress on stderr; redirected output contains no mandatory ANSI escapes. Support `--help`, `--version`, color policy, and documented interruption behavior. Map library status to exits: 0 only for a trustworthy met contract, 1 for completed contract failure, 2 for configuration/infrastructure failure; use documented POSIX 130 for user SIGINT after partial evidence finalization. Infrastructure takes precedence over survivors. The library never calls exitWith.

### M3: Parity and usability


Add `examples/minimal/heni.json` and shell/Python invocation recipes that call `heni` instead of reimplementing mutation orchestration. Add `docs/cli.md` and start `docs/troubleshooting.md` with every result class and recovery action. Compile the same case definition through library and manifest, execute both, normalize volatile IDs/timings/paths, and compare outcomes, stage decisions, and evidence meaning. Test schema/decoder agreement with a shared positive and negative corpus; do not rely on hand-maintained schema prose alone.

Apply the relevant [CLI guidance](mori://shinzui/haskell-jitsurei/docs/cli-overview): clear grouped options, terminal-aware help, and reliable version output. Keep agent launchers, fzf, clipboard helpers, and layered service configuration out of this small tool. The executable must report a package version from source archives without requiring Git metadata. Record wire versioning and compatibility decisions in a local ADR. Optional framework/resource owners may add fields later, but this plan retains schema and lowering ownership.


## Concrete Steps


Locate parser/JSON dependencies in Mori and verify their released versions before selecting bounds. After creating the executable and fixtures:

```bash
cabal build heni-cli:exe:heni
cabal run heni-cli:exe:heni -- check examples/minimal/heni.json
cabal run heni-cli:exe:heni -- list examples/minimal/heni.json
cabal run heni-cli:exe:heni -- run examples/minimal/heni.json --case guard-bypass --output .heni-runs/cli-smoke
cabal run heni-cli:exe:heni -- report .heni-runs/cli-smoke/report.json
cabal test heni-cli:heni-cli-test --test-show-details=direct
```

Use fresh output directories. The guard-bypass case must be caught with exit 0; a supplied surviving case must exit 1. A typo such as `timeuotSeconds` must fail with exit 2 and a field location before candidate execution. These commands are acceptance targets to implement, not currently available commands.


## Validation and Acceptance


Run positive manifests and invalid unknown-key/version/duplicate-key/reference/path/budget cases. Check both schema validation and decoder results, including nested objects and explicit nulls. `check` must not create the test-stage sentinel. `list` must not spawn anything. An unmatched run fails by default. A malformed stored report gives a clear error and executes no commands. The correct generic diagnostic produces identical library and CLI verdicts; wrong build failure, timeout, and missing selection cannot yield exit 0.

Redirect stdout and stderr independently and inspect clean JSON/human outputs. Ctrl-C must preserve partial evidence and use the documented exit. Report rendering works after moving the directory. Secret-bearing options are redacted in output while explaining the limitation. Unsupported Haskell hook serialization fails explicitly. Document exactly which later adapter/resource capabilities are not yet available; reconcile them before final migration acceptance.


## Idempotence and Recovery


Validation and listing are repeatable. Applicability checks mutate only disposable copies. Runs allocate fresh outputs and never overwrite existing evidence. Reporting is read-only; journal recovery does not resume execution. Do not add publication or cross-repository writes to these commands. If wire shape changes before release, update schema, decoder, examples, golden fixtures, and relevant plans together.


## Interfaces and Dependencies


Hard prerequisite: `docs/plans/4-run-baseline-to-report-mutation-campaigns.md`. This plan owns manifest decoding/schema, CLI arguments/help/rendering, and exit mapping. It consumes the library's classifier and report writer without duplicating them. `docs/plans/6-add-named-test-adapters-replay-and-crash-evidence.md` and `docs/plans/7-add-resource-aware-workers-and-verified-reuse.md` integrate new evidence/resource capabilities through this owner; their standalone library tests need not wait on this plan. `docs/plans/8-prove-representative-script-migration-and-usability.md` requires their final portable forms and combined parity. Keep all framework packages and terminal libraries out of heni's generic execution model.
