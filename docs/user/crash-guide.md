---
type: Guide
title: "Attribute a native crash from Haskell"
description: "Place a fresh reachability probe and distinguish real signals from missing probes, numeric exits, and timeouts."
docId: DOC-22
tags: ["haskell", "posix", "signals", "crash-probes"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T23:15:20Z
sources:
  - resource: examples/haskell-guides/GuideCases.hs
  - resource: src/Test/Heni/Crash.hs
  - resource: test/adapter/Main.hs
---

# Attribute a native crash from Haskell

Use `CrashProbe signal name` only for a fault whose declared contract is an actual
native signal after a specific operation is reached. Import platform constants
from `System.Posix.Signals`; hard-coded signal numbers are not portable.
Use `GenericCommands` evidence mode: crash probes have their own attempt-bound
channel and cannot use `StructuredTestsV1`.

In the cooperating Haskell program, call `recordCrashProbe` immediately before
the operation. The compiled example uses `sigTERM` to demonstrate a real native
termination without requesting an abort core dump. Its negative cases deliberately
omit the probe, use another signal, return a numeric exit, or time out:

```haskell
crashFixture :: String -> IO ()
crashFixture mode = do
  changed <- (== "mutant\n") <$> readFile "mode.txt"
  if not changed
    then pure ()
    else do
      unless (mode == "missing-probe") (recordCrashProbe "operation-reached")
      case mode of
        "good" -> raiseSignal sigTERM
        "missing-probe" -> raiseSignal sigTERM
        "wrong-signal" -> raiseSignal sigKILL
        "numeric-exit" -> exitWith (ExitFailure (128 + fromIntegral sigTERM))
        "timeout" -> threadDelay 3000000
        _ -> error "unknown crash example mode"
```

Outside Heni, `recordCrashProbe` is a no-op; it does not suppress the subsequent
operation or signal. Run the campaign mode, rather than invoking the example's
internal fixture crash modes directly.

The [campaign definition](../../examples/haskell-guides/GuideCases.hs) uses
`CrashProbe (fromIntegral sigTERM) "operation-reached"` and edits `mode.txt` from
`safe` to `mutant`. The unchanged baseline returns successfully before any native
termination is permitted. It uses the directly invoked example executable, so
there is no shell to convert a native signal into a normal numeric exit.

```sh
cabal run heni:exe:heni-haskell-guides -- crashes .heni-runs/guide-crashes
```

| Case | Expected verdict | Evidence distinction |
| --- | --- | --- |
| `good` | `Caught` / `ExplicitCrash` | Fresh named probe plus actual `sigTERM`. |
| `missing-probe` | `WrongFailure` | Correct signal alone does not prove the declared reachability. |
| `wrong-signal` | `WrongFailure` | A fresh probe cannot substitute for the expected signal. |
| `numeric-exit` | `WrongFailure` | Normal exit `128 + signal` is still an exit. |
| `timeout` | `TimedOut` | Printing/writing a probe before hanging does not prove detection. |

The campaign is `RunFailed`; the example executable verifies all five outcomes
and then exits 0. Every fixture has a 500 ms test budget, including its unchanged
baseline, so heavily loaded hosts may need a larger test budget and a correspondingly
longer timeout demonstration. A candidate build still must succeed. No named-test
adapter or output scraping is involved.

Probe files bind the run, case, role, stage, and fresh attempt. Do not reuse a
previous probe artifact, prewrite one in a snapshot, or let a shell wrapper
translate its process outcome. Missing/stale/wrong probes reject attribution.
The existing [adapter conformance suite](../../test/adapter/Main.hs) also exercises
stale identities. A probe establishes reachability, not arbitrary crash root cause.
[POSIX supervision](process-supervision.md) describes detached-process and
cancellation boundaries; [report consumption](report-consumption-guide.md) shows
how to inspect the retained native signal and relative log references.
