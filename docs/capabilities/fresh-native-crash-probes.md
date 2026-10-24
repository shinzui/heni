---
type: Capability
title: "Fresh native crash-probe attribution"
description: "Accept an explicitly declared native signal only with a fresh case-specific reachability probe and valid execution evidence."
capabilityId: CAP-9
provider: mori://shinzui/heni
status: shipped
stability: experimental
since: unreleased
packages: ["heni"]
interface: ["Test.Heni.Crash.recordCrashProbe", "CrashProbe", "expect.kind: crash"]
tags: ["mutation-testing", "haskell"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T23:16:53Z
reviews:
  - kind: model
    reviewer: codex/gpt-6
    reviewed_at: 2026-10-24T23:16:53Z
    document_timestamp: 2026-10-24T23:16:53Z
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
requires: ["CAP-3", "CAP-4"]
evidence:
  - kind: module
    resource: src/Test/Heni/Crash.hs
    proves: "Writes and validates fresh attempt-bound probe evidence."
  - kind: test
    resource: test/adapter/Main.hs
    proves: "Distinguishes fresh native crash detection from missing/stale/wrong probes and incompatible outcomes."
  - kind: guide
    resource: docs/user/adapters.md
    proves: "Shows signal/probe declaration and its reachability-only meaning."
  - kind: guide
    resource: docs/user/crash-guide.md
    proves: Worked Haskell adoption with compiled example source.
  - kind: example
    resource: examples/haskell-guides/GuideCases.hs
    proves: Runnable public-API recipe with checked expected outcomes.
---

# Fresh native crash-probe attribution

Declare a native signal and nonempty probe name, then call
`recordCrashProbe` immediately before the relevant operation in the cooperating
program. Detection requires the actual native signal, matching fresh attempt
identity, and no timeout/cancellation or validity failure. An ordinary numeric
exit or printed marker cannot replace a signal and probe.

This channel needs no Tasty/Hspec adapter. POSIX signal numbers are platform
specific. A reachability probe establishes that the operation was reached; it
does not identify the arbitrary root cause of a crash. Explicit crashes are
reported separately from semantic assertion detections.

Builds on [POSIX supervision](bounded-posix-processes.md) (CAP-3) and
[evidence-owned verdicts](attributable-verdicts.md) (CAP-4).
See the [adapter/crash reference](../user/adapters.md).

See the [worked Haskell guide](../user/crash-guide.md) and its compiled example.
