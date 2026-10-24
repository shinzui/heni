---
id: 7
slug: add-resource-aware-workers-and-verified-reuse
title: "Add resource-aware workers and verified reuse"
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

# Add resource-aware workers and verified reuse


This ExecPlan is a living document. Maintain Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective. Record implementation friction with `agents/skills/exec-plan/record-friction.ts` under this plan. Follow `agents/skills/exec-plan/ADR.md` before ADR changes, and distill durable decisions before completion. All commands below run from the repository root unless stated otherwise. Paths named as new files are planned artifacts, not claims that they already exist.


## Purpose / Big Picture


Users can run independent cases concurrently, safely serialize shared resources, and reuse baseline/build work where the evidence supports it. The library manages acquire/use/release lifetimes and worker isolation so performance improvements do not turn resource collisions or stale builds into apparent detections.


## Progress


- [ ] M1: Scoped resources acquire and release correctly under success, failure, and cancellation.
- [ ] M2: Bounded workers preserve serial verdicts and obey resource limits without shared writable trees.
- [ ] M3: Verified baseline/build reuse reduces repeated work without accepting stale evidence.


## Surprises & Discoveries


None yet.


## Decision Log


No implementation decisions yet; the approach below is the initial proposed contract.


## Outcomes & Retrospective


To be filled during implementation, including acceptance evidence, remaining limits, and friction triage.


## Context and Orientation


Hard prerequisite: `docs/plans/4-run-baseline-to-report-mutation-campaigns.md` Complete. It establishes fresh-copy serial execution and exactly-once result accounting. Read spec sections 5, 8, and 10 and RES-2's resource/cache observations. `docs/plans/5-expose-strict-manifests-and-the-shared-cli.md` is a soft dependency because the library can be tested before CLI options exist.

A resource claim names a shared external fixture and its allowed concurrency. A resource epoch identifies the relevant prepared state; changing it invalidates assumptions about a baseline. A worker is an owned sequence of case executions with an exclusive source/build tree. Reuse means retaining verified work within one campaign, not trusting previous run verdicts. A baseline key describes all inputs whose identity must match before sharing that baseline.

No local ADR existed at creation. Read and link prerequisite workspace, process, and report decisions before changes. This plan owns the new durable resource/scheduling/reuse decision, preserving the public plain-IO consumer boundary supported by [the inspected base-library ADR](mori://shinzui/mori-app/okf/adrs/concepts/ADR-1).


## Plan of Work


### M1: Scoped lifetimes


Implement `src/Test/Heni/Resource.hs` with scoped providers that run a callback while a resource is available and release it afterward. Support campaign-, worker-, and case-scoped setup explicitly. Define typed setup/teardown results, namespaced environment additions, and resource identity/version metadata. Compose acquisition in declaration order and release in reverse order; if a later acquisition fails, release earlier acquisitions. Use masked ownership transitions with interruptible work, and preserve both primary and cleanup errors. External command hooks use the shared process supervisor with separate setup/teardown budgets; Haskell callbacks use the documented trusted-IO contract. Uninterruptible foreign calls cannot be given a false bounded-shutdown guarantee.

Do not claim workspace cleanup rolls back databases or services. Consumers must supply reset/teardown semantics. Baseline and mutant receive equivalent resource state; a case that changes shared state needs reset/reprovisioning or a new epoch before reuse. Default external-resource concurrency to one unless the consumer explicitly declares independent instances or a higher safe capacity. Provide scoped command hooks in the manifest through the schema owner and typed hooks for richer Haskell consumers.

### M2: Bounded scheduling


Implement `src/Test/Heni/Scheduler.hs`. Default to one worker, allow an explicit bounded count, and keep deterministic selection/report order even when completion order differs. Each worker owns a distinct mutable tree, build directory, artifact namespace, and resource bindings. Resource capacity limits apply across all workers in the campaign. Acquire multiple claims in canonical order or atomically so two cases cannot deadlock while each holds half of the required resources. Scheduling must not starve a queued case indefinitely.

On cancellation or failure, stop scheduling, terminate active commands, release resources, and finalize every selected ID once. Use explicit ownership records to prevent double release or duplicate final results. Shared resources across separate concurrent Heni processes are not coordinated by an in-memory semaphore; document that consumers need external locks or independent namespaces. Do not derive available port numbers by adding worker IDs and claim they are reserved. Allow providers to return genuinely allocated ports or paths.

### M3: Conservative reuse and measurements


Add opt-in reuse after fresh-worker execution remains a reference mode. Cache baselines only within the campaign and only for matching snapshot bytes/policy, command/environment contract, selector, adapter/version, build configuration/toolchain, and resource identity/epoch. Keep sensitive environment comparison in memory; portable reports record redaction and nonsecret identity without publishing weak hashes of secrets. If an input or external resource cannot be represented reliably, disable reuse and explain why.

Allow incremental build reuse only within one worker after restoring source bytes and verifying that the build tool observes the restored and mutated inputs. Preserve private build directories; never share writable candidate artifacts across workers. Prove rebuild invalidation with edits that reverse each other and same-size content changes, including coarse timestamp behavior. If generic commands offer no reliable invalidation contract, keep fresh builds as the default and expose a documented opt-in provider. A failed reset, unexpected generated file, cleanup error, or suspicious build invalidation retires the worker and its cache; continue only from a fresh snapshot.

Add `test/scheduler/`, self-contained resource fixtures, and `bench/campaign/` workloads. Measure baseline invocation count, cold/warm elapsed time, compilation time, and peak concurrency separately. State the total resource budget as workers multiplied by per-build jobs plus fixture capacity; do not silently multiply unlimited Cabal jobs. Publish observations in `docs/design/scheduling.md` without promising universal speedups. Cross-run persistent verdict caching and coverage selection remain out of scope.


## Concrete Steps


Add `heni-scheduler` and a deterministic benchmark executable `heni-campaign-bench` with fresh and reuse modes. Locate concurrency libraries through Mori before API use, then verify Hackage/upstream releases.

```bash
mori registry search async
mori registry search stm
cabal test heni:heni-scheduler --test-show-details=direct
cabal test heni:heni-runner --test-show-details=direct
cabal run heni:exe:heni-campaign-bench -- --workers 1 --mode fresh
cabal run heni:exe:heni-campaign-bench -- --workers 2 --mode reuse
```

Use deterministic local fixture resources, never a required broker/database. If the CLI exists, add `--jobs` and the portable resource/reuse options through its owner, then compare the corresponding runs. Record compiler, OS, machine, and repeated-run variance for timing observations.


## Validation and Acceptance


Assert acquisition/release counts under normal completion, setup failure after partial acquisition, failing test, timeout, callback exception, and cancellation. A capacity-one fixture must never observe simultaneous users even with multiple workers; independent fixtures should overlap. Two-resource cases in opposite declaration orders must complete without deadlock. Source/build/log writes from one worker must be invisible to another. Serial and parallel campaigns produce equivalent per-ID outcomes after normalizing timing/order.

Reuse must reduce baseline invocation count for identical compatible cases and rerun after changing tests, fixtures, command arguments, environment contract, selector, adapter, build options, or resource epoch. Compare cached and fresh outcomes on an adversarial alternating-edit fixture. A reset failure must retire the worker, and the next case must execute correctly in a fresh tree. Cancellation leaves one final record for queued/running/completed cases and releases all successfully acquired resources. Timing results are evidence, not pass/fail thresholds; isolation and invocation-count invariants are the release gates.


## Idempotence and Recovery


Reuse is confined to a single campaign's owned directories. A new invocation starts with a new snapshot and no trusted verdict cache. A corrupted worker is discarded; its retained logs remain outside the disposable tree. Resource teardown failures invalidate run confidence and remain visible; do not blindly retry non-idempotent external setup/teardown. Document which consumer hooks are retryable and use new fixture identities for safe test reruns.


## Interfaces and Dependencies


Hard prerequisite: `docs/plans/4-run-baseline-to-report-mutation-campaigns.md`; soft dependency: `docs/plans/5-expose-strict-manifests-and-the-shared-cli.md`. This plan owns scoped providers, resource claims, worker scheduling, reuse identity, and cache invalidation. It consumes snapshot/reset verification and process cleanup; it must not bypass either. Changes to `Runner.hs` preserve the original serial path as a reference test.

The manifest owner defines portable command hooks/options and the report owner serializes resource identity, reuse decisions, and timing evidence. `docs/plans/8-prove-representative-script-migration-and-usability.md` integrates these with named adapters and CLI parity. Arbitrary Haskell resource values stay out of JSON and are interpreted in the caller's own IO context.
