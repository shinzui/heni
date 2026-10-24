---
type: Capability
title: "Bounded POSIX command supervision"
description: "Run literal argv with wall-clock budgets, bounded retained output, exact diagnostic witnesses, and owned process-group cleanup."
capabilityId: CAP-3
provider: mori://shinzui/heni
status: shipped
stability: experimental
since: unreleased
packages: ["heni"]
interface: ["Test.Heni.Process.runCommand", "Test.Heni.Command.Command"]
tags: ["mutation-testing", "haskell"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:59:21Z
reviews:
  - kind: model
    reviewer: codex/gpt-6
    reviewed_at: 2026-10-24T23:01:10Z
    document_timestamp: 2026-10-24T22:59:21Z
    scope: content-and-metadata
    outcome: commented
    provider: openai
    model: gpt-6
    effort: unspecified
    context: >-
      Author self-review against the listed local source, test definitions, and
      examples, including evidence-path and dependency-link checks. Availability
      means implemented on the default branch, not a Hackage release. No
      independent approval or new execution of every cited test is claimed.
evidence:
  - kind: module
    resource: src/Test/Heni/Process.hs
    proves: "Exposes supervised command execution and observation."
  - kind: test
    resource: test/process/Main.hs
    proves: "Exercises exit versus signal, floods, cross-chunk witnesses, timeout, descendants, cancellation, and containment limits."
  - kind: guide
    resource: docs/user/process-supervision.md
    proves: "Documents budgets, evidence retention, process ownership, and cleanup guarantees."
---

# Bounded POSIX command supervision

Run executable-plus-argv in a checked workspace directory with explicit
environment additions/removals. POSIX groups, concurrent stream draining, and
bounded shutdown distinguish ordinary exits, native signals, timeout, and
cancellation. Raw retained output is bounded while requested diagnostic bytes
can still be matched beyond that retained prefix.

The supervisor terminates remaining owned group members and preserves primary
and secondary cleanup errors. Detached sessions/groups, abrupt runner SIGKILL,
and uninterruptible hooks need consumer-owned containment. This implementation
is POSIX-only; it does not provide Windows supervision or a security sandbox.
Embedding executables require the threaded runtime.

See [process contracts](../user/process-supervision.md) for the exact bounds and
the executable test fixture's coverage.
