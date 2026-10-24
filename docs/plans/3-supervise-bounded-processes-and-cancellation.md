---
id: 3
slug: supervise-bounded-processes-and-cancellation
title: "Supervise bounded processes and cancellation"
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
      at: 2026-10-24T15:17:29Z
      mode: "implement"
      note: "Implement bounded POSIX process groups, concurrent log drains, witness retention, and cancellation evidence"
---

# Supervise bounded processes and cancellation


This ExecPlan is a living document. Maintain Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective. Record implementation friction with `agents/skills/exec-plan/record-friction.ts` under this plan. Follow `agents/skills/exec-plan/ADR.md` before ADR changes, and distill durable decisions before completion. All commands below run from the repository root unless stated otherwise. Paths named as new files are planned artifacts, not claims that they already exist.


## Purpose / Big Picture


A caller can launch a structured command, bound its runtime and output, cancel it, and learn whether it exited, received a signal, timed out, or failed to start. Owned subprocesses are cleaned up, and the evidence remains usable even when output is large or the direct child exits before its descendants.


## Progress


- [x] M1 (2026-10-24; literal argv, launch, exit and SIGABRT fixtures pass): Structured commands produce bounded, distinct exit/signal/launch evidence.
- [x] M2 (2026-10-24; timeout, ignored SIGTERM, inherited pipes and repeated cancellation pass on macOS): Timeout and cancellation clean up owned process groups on Linux and macOS.
- [x] M3 (2026-10-24; dual-stream flood, retained split witness, invalid UTF-8 and observer failure tests pass): Output limits, callback failure, and cleanup errors preserve trustworthy evidence.


## Surprises & Discoveries


The process package reports POSIX signal termination as negative ExitFailure; an ordinary positive shell-style code must remain a normal exit. Raw log truncation and unavailable classifier evidence are separate facts: exact requested byte witnesses can remain complete after logs stop retaining bytes.


## Decision Log


2026-10-24: Use a narrow POSIX group adapter over released process/unix APIs, not shell exit conventions. Group cleanup remains bounded even if the leader exited; detached sessions are outside the contract.

2026-10-24: Scan diagnostic UTF-8 bytes independently per stream and retain exact witnesses separately. Only proved witness text enters classifier evidence, avoiding false matches introduced by lenient decoding. See [the process ADR](../adr/4-posix-process-ownership.md).


## Outcomes & Retrospective


`cabal test heni:heni-process heni:heni-unit --test-show-details=direct` passes on macOS/GHC 9.12.4. The fixture is a declared Cabal build tool with an outer watchdog. It covers literal arguments, launch failure, actual signal versus exit, witness-before-timeout, concurrent output flooding, bounded retained logs, chunk-spanning witnesses, invalid UTF-8, ignored SIGTERM, leader-exit pipe inheritance, repeated cancellation and observer failure. The detached fixture is explicitly cleaned up and documents the supervision boundary. Linux execution is configured in CI and remains a final release gate. FRIC-2 is accepted: Fourmolu rejected a compiling explicit-brace nested case, so the same expression now uses ordinary indented layout. Ownership and limitations are distilled in docs/adr/4-posix-process-ownership.md.


## Context and Orientation


Begin after `docs/plans/1-establish-the-public-model-and-executable-api-contracts.md` is Complete. It supplies `Command`, `StageBudget`, `ProcessOutcome`, `StageEvidence`, and typed errors. Read `docs/initial-spec.md` sections 7–8 and 10, and `docs/research/ecosystem-mutation-testing-design.md`. A process group is the operating system's collection of related child processes that can receive a termination signal together. Reaping means waiting for an exited direct child so its OS bookkeeping is collected.

Mori locates [the process package](mori://haskell/process/packages/process), whose local source documents that termination is an attempt, not a guarantee. Do not assume terminating a `ProcessHandle` proves every descendant is gone. Inspect the actual released APIs and platform implementations before coding. No local ADR existed at plan creation; the prerequisite's boundary decisions apply, and this plan adds a process ownership/platform-limits ADR.


## Plan of Work


### M1: Launch and evidence


Implement `src/Test/Heni/Process.hs` and `Internal/Process/Posix.hs`. Accept executable plus argument vector, validated workspace-relative working directory, explicit environment overrides/removals, stage budget, grace budget, and output policy. No implicit shell interpolation: an explicit shell executable remains a deliberate caller choice. Resolve executable availability during validation and handle later launch races as infrastructure failures. Use monotonic elapsed time for budgets and wall-clock timestamps only for report presentation. Preserve normal exit, signal termination, and runner-enforced termination as distinct constructors; an exit code numerically resembling a signal is not a proven signal.

Create an owned child process group/session before unmasking cancellation. Scope handles, pipe-draining workers, and the process lifetime with exception-safe acquisition/release. Recheck dependency APIs using Mori, then registry/tag versions. If process alone cannot expose reliable POSIX signal/group behavior, add a narrow unix-backed platform implementation rather than interpreting shell exit conventions. Keep that dependency behind the platform module, with Windows explicitly unsupported for now.

### M2: Bounded shutdown


On timeout, cancellation, callback exception, or pipeline failure, stop accepting work, send the documented graceful group termination, wait only the configured grace interval, escalate to forced group termination, and reap the direct child. Close owned handles and join output readers with bounded waits. Handle a direct child that exits while descendants keep pipes open, descendants ignoring termination, cancellation during spawn, and signal arrival while finalizing. Do not catch asynchronous cancellation as an ordinary successful result or swallow it indefinitely. The runner must receive enough evidence to finalize partial results and then honor cancellation.

Document the supported contract: descendants remaining in the owned process group are terminated; deliberately detached descendants can escape ordinary POSIX group supervision. Commands requiring stronger containment need an external sandbox. Abrupt runner SIGKILL or machine loss cannot execute cleanup; document possible orphaned children and safe ownership-based recovery instead of promising normal cancellation guarantees for those events. Test and state that limit instead of promising arbitrary descendant cleanup. If cleanup cannot complete within its bound, return explicit infrastructure evidence and invalidate the worker. The elapsed-time assertion permits a small CI scheduling tolerance over timeout plus grace, stated in the test rather than a brittle exact duration.

### M3: Logs without false witnesses


Drain stdout and stderr concurrently to avoid pipe deadlock. Store bounded logs with byte counts, truncation markers, relative artifact references, and source stream identities. Evaluate diagnostic matching incrementally across chunk boundaries, preserve the exact matched witness in a dedicated bounded evidence record, and distinguish bytes from decoded display text. Invalid output UTF-8 must not crash the supervisor. If the configured policy prevents proving a witness, produce evidence-unavailable/infrastructure information, never a caught result based on missing data. Avoid storing inherited environment values or secrets; allowlisted overrides need explicit redaction metadata.

Create `test/process/` and a small `heni-fixture` test executable with modes for known exit, signal, long-running child/grandchild, ignored graceful shutdown, stdout/stderr flooding, argument echo, and inherited-pipe behavior. The fixtures must be self-contained Haskell/POSIX programs, not depend on Bash/Python or external services. Add tests for simultaneous completion/timeout races, interrupted log writes, launch failure, observer failure, and repeated cancellation. `docs/design/process-supervision.md` records platform evidence and limitations.


## Concrete Steps


Inspect source via Mori; do not traverse `/nix/store` to find dependency code.

```bash
mori registry show haskell/process --full
mori registry docs haskell/process
mori registry search unix
mori registry search async
cabal build heni:exe:heni-fixture
cabal test heni:heni-process --test-show-details=direct
cabal test heni:heni-unit --test-show-details=direct
```

Add `heni-process` as a Cabal test suite whose fixture executable is declared as a build tool rather than located through a developer-specific path. CI must run the process suite on both supported operating systems. Record the exact observed signal and descendant behavior in the design document.


## Validation and Acceptance


Arguments containing spaces, quotes, dollar signs, and shell metacharacters arrive literally. Missing executables are infrastructure errors. A child exiting 1 differs from a child terminated by a signal and from a timeout. A process that prints the expected diagnostic then hangs is still timed-out. Flooding both streams completes or times out without deadlock or unbounded resident memory. Witnesses split across output chunks match correctly and remain available after log truncation.

Cancellation during spawn, execution, and log collection leaves no owned running child/group member after the shutdown allowance. Use marker/PID handshakes to prove descendant termination rather than relying only on sleeps. A detached-child fixture documents the supported boundary and the test itself cleans up that fixture safely. Check bounded behavior when a child ignores graceful termination and when pipe writers outlive the leader. Capture primary and cleanup errors together. A callback failure cannot strand children. Run under an outer watchdog so a broken supervisor fails a test rather than hanging the full suite.


## Idempotence and Recovery


Fixtures allocate fresh directories and group identities. Cleanup targets only verified owned processes and handles, never a broad process-name search or unrelated PID. Avoid PID reuse races by retaining ownership handles and testing group lifetime. Failed tests leave enough PID/log metadata for diagnosis, with bounded test-level cleanup. Retry with a new fixture; do not treat earlier logs as current execution evidence.


## Interfaces and Dependencies


Hard prerequisite: `docs/plans/1-establish-the-public-model-and-executable-api-contracts.md`. Workspace path behavior from `docs/plans/2-implement-isolated-snapshots-and-checked-mutations.md` is a soft dependency; temporary fixture directories suffice for this plan. The API is an effectful `runCommand` returning structured process/stage evidence, with a cancellation mechanism that permits the campaign runner to finalize then propagate interruption. It does not classify mutations or call exitWith.

`docs/plans/4-run-baseline-to-report-mutation-campaigns.md` consumes this supervisor for every external command, including patch application. Replay and resource-hook command paths must use it too. Progress callbacks are observation, not authority over results. Dependency bounds and supported GHC combinations require released-package checks and CI evidence; no version is implied by this plan.
