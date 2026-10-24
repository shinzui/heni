---
type: Reference
title: "Process ownership and evidence"
description: "Look up POSIX command supervision, output retention, timeout, and cleanup guarantees."
docId: DOC-8
tags: ["posix", "processes", "timeouts"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:57:52Z
sources:
  - resource: src/Test/Heni/Process.hs
  - resource: test/process/Main.hs
---

# Process ownership and evidence

`runCommand` launches executable plus literal argv in the workspace (or a
checked relative directory) with explicit environment overrides and removals.
It inherits other environment entries for execution but never records them.
`validateExecutable` provides preflight diagnostics; launch races still become
LaunchFailed evidence. Heni uses a POSIX process group, masked acquisition,
monotonic wall-clock budgets, and two concurrently draining output threads.
Embedding executables must enable the GHC threaded runtime.

The supervisor distinguishes a normal exit, negative process-package signal
status, timeout and cancellation. Shell exit 128+signal is only an exit code.
On every completion path it sends SIGTERM to remaining owned group members,
waits up to the grace budget, then sends SIGKILL and polls direct-child reaping
within another grace budget. This handles a leader exiting while a descendant
retains the pipes, and descendants ignoring SIGTERM. Group shutdown is briefly
uninterruptible around bounded nonblocking polling, so repeated asynchronous
cancellation cannot skip escalation. Output-reader joins and log flushes defer
further cancellation until their bounded cleanup completes.

Each stream retains at most its configured bytes, with total bytes seen and
truncation recorded in LogArtifact. Diagnostics are scanned as UTF-8 bytes
through all chunks with sufficient overlap, independently per stream. Requested
witnesses total at most 64KiB; exact matched witnesses remain in the report even
when the raw log stopped retaining data. Only these byte-proved witnesses enter
StageEvidence.transcript. Display decoding cannot fabricate a match from
invalid UTF-8. A raw log artifact's truncation is distinct from stage evidence
being unavailable. ProcessReport retains primary evidence and secondary reader,
shutdown and log errors. Observer failure terminates the group and produces
infrastructure information.

Asynchronous cancellation raises ProcessAborted with final process evidence and
the original exception. A campaign must finalize its selected ledger before
rethrowing that cause. The library never exits the host program or prints
mandatory output. Arbitrary observers/hooks are trusted IO and must cooperate
with cancellation; hostile uninterruptible code cannot be contained by this API.

Local `heni-process` execution on macOS/GHC 9.12.4 proves literal metacharacter
arguments, exit 1 versus SIGABRT, witness-before-timeout, simultaneous 6.5MiB
stdout/stderr floods capped to 1024 bytes each, cross-chunk witness retention,
malformed UTF-8, leader/descendant pipe inheritance, ignored SIGTERM, observer
failure and cancellation. Its outer watchdog is 20 seconds; shutdown assertions
allow two seconds of CI scheduling tolerance. Linux runs are configured in CI
and remain part of final release evidence.

Descendants deliberately creating a new session/group can escape supervision.
The detached fixture proves this boundary and explicitly kills its owned PID.
Abrupt runner SIGKILL, power loss and uninterruptible kernel operations cannot
execute normal cleanup. Stronger guarantees require an external sandbox.
No process-name search or broad PID sweep is an authorized recovery method.
