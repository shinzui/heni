---
type: Reference
title: "Named assertions, replay and native probes"
description: "Look up named assertion, replay, and native crash evidence contracts."
docId: DOC-11
tags: ["adapters", "named-tests", "replay", "crash"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:57:52Z
sources:
  - resource: src/Test/Heni/Adapter.hs
  - resource: test/adapter/Main.hs
---

# Named assertions, replay and native probes

The [Haskell crash guide](crash-guide.md) provides a runnable native signal example
with missing-probe, wrong-signal, numeric-exit, and timeout counterexamples.

Install `heni-tasty` or `heni-hspec` in the consumer test executable. Replace
Tasty's `defaultMain` with `Test.Heni.Tasty.heniMain`, or Hspec's `hspec` with
`Test.Heni.Hspec.heniHspec`. Ordinary direct execution keeps the native runner.
Inside an attempt the reporter writes a dedicated versioned JSON Lines file;
stdout, colors and display formatting are not the protocol.

Set `adapter: "heni-v1"` in a manifest case and use
`expect: {"kind":"named-tests","failures":["suite/intended"],"replayRequired":false}`.
Stable IDs join nested groups/example names with `/`, escaping literal `~`
and `/` as `~0` and `~1`. Duplicate IDs are rejected. Tasty selectors use native
pattern syntax; Hspec selectors match substrings of the stable ID. Both
intersect with native command filters. Tasty and Hspec report exact selected
and executed IDs; unfiltered discovery is currently unknown, not invented.
Hspec history reruns and dry-run are unsupported inside an attempt. Fail-fast partial
execution is infrastructure evidence, never a completed successful detection.

The core requires an unchanged baseline with the intended tests executed and
passed. A candidate must fail precisely the allowed named assertions. Skips,
setup errors, other failures, count mismatches and incomplete records cannot
count as caught. Every record binds run, case, stage, role and fresh attempt.
Producer version must agree with baseline. The protocol and reporters are an
evidence contract for cooperating programs, not an attestation against a
malicious executable.

For QuickCheck with Hspec, wrap one explicitly selected property example:

```haskell
it "property" $ heniProperty "suite/property"
  (QC.stdArgs {QC.maxSuccess = 1, QC.maxSize = 30}) property
```

Use `replayRequired: true`. The helper records QuickCheck's native seed/size,
version, generator arguments and counterexample. Heni supervises a separate
Replay stage on the same edited workspace. Missing/invalid tokens, changed
configuration, another failure or replay timeout reject reproduction; original
and replay facts remain available. One replay property per selected attempt
is supported. Other frameworks can supply `CaseHooks.replayBuilder` and emit
the same protocol. Counterexamples may contain sensitive application data;
the consumer must redact them before recording when needed.

For a declared native crash use
`expect: {"kind":"crash","signal":6,"probe":"operation-reached"}`
and call `Test.Heni.Crash.recordCrashProbe "operation-reached"` immediately
before the operation. Signal numbers are platform-specific; Haskell users can
use `System.Posix.Signals`. This channel requires no test adapter. Fresh
identity, the declared signal and absence of timeout/cancellation are all
required. A probe proves reachability, not the cause of an arbitrary crash.
Numeric exits and ordinary stdout markers do not prove a native signal.

`adapters/heni-tasty/test/fixture/Main.hs` and
`adapters/heni-hspec/test/fixture/Main.hs` are complete runnable examples.
The core standalone producer tests keep both frameworks outside its dependency
closure. `schemas/test-evidence-v1.schema.json` documents record shape; the
reader additionally verifies sequence, membership, transitions and totals.
