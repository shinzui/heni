---
type: Guide
title: "Implement verified build reuse in Haskell"
description: "Connect a content-aware GHC build wrapper to BuildReuse and reject stale observations before running tests."
docId: DOC-23
tags: ["haskell", "build-reuse", "content-identity", "ghc"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T23:15:20Z
sources:
  - resource: examples/haskell-guides/GuideBuild.hs
  - resource: src/Test/Heni/BuildReuse.hs
  - resource: test/scheduler/Main.hs
---

# Implement verified build reuse in Haskell

`RunOptions.buildReuse` retains private worker artifact directories only when a
trusted consumer provider can verify what the build observed. It is separate
from `ReuseBaselines`, which shares passing baseline evidence. Start with fresh
execution, establish identical outcomes under retention, then verify that stale
observations fail before tests. No manifest flag can supply this Haskell function.

The runnable [GuideBuild.hs](../../examples/haskell-guides/GuideBuild.hs) implements
a narrow real GHC build contract for exactly `Subject.hs` and `Checker.hs`, with
base-only imports and fixed compiler flags. Its cache is addressed by staged
content identity; a new identity triggers forced compilation. A previously
completed entry for the same identity can reuse its compiled binary.
This demonstrates safe reuse of completed input versions rather than claiming a
general Cabal incremental invalidation algorithm or a universal speedup.

## Define the consumer build contract

Heni supplies `HENI_BUILD_INPUT_ID` for a retained candidate. The cooperating build
wrapper performs these steps:

1. Read the staged source and put exact copies under `.heni-build/<input-id>/`.
2. Compile the copied checker with GHC, an explicit import path, `-package-env -`,
   and `-fforce-recomp` on a cache miss. Outputs stay inside the retained directory.
3. Write a completion marker only after GHC succeeds. On a cache hit, require the
   marker, executable, and copied inputs to match.
4. Publish the active input receipt used to select the binary for the test command.

The compiler subprocess inherits the supervised wrapper's process group. Heni
bounds the whole build stage. The example contract identity includes the resolved
GHC executable path and `--numeric-version`, and version `guide-content-ghc/v1`
represents the fixed flags/input policy. A real integration must also represent
package databases, native tools/libraries, generated inputs, relevant environment,
and changed build-wrapper semantics in its contract. Those external inputs are
not made observable merely by reading the input ID environment variable.

## Supply a verifier

With `Build` imported from `Test.Heni.BuildReuse` and `W` from
`Test.Heni.Workspace`, the provider is:

```haskell
contentAddressedReuse :: Text.Text -> Build.BuildReuse
contentAddressedReuse toolchain = Build.BuildReuse
  toolchain
  [target ".heni-build"]
  (const (pure ()))
  $ \workspace expected -> do
    let root = W.workspaceRoot workspace
        key = Text.unpack expected
        directory = root </> ".heni-build" </> key
    observed <- readFile (root </> ".heni-build/active-input")
    completed <- readFile (directory </> "completed")
    binaryExists <- Dir.doesFileExist (directory </> "checker")
    same <-
      and
        <$> mapM
          (\file -> (==) <$> BS.readFile (root </> file) <*> BS.readFile (directory </> file))
          inputFiles
    pure $
      if observed == key && completed == key && binaryExists && same
        then Right ()
        else Left "build receipt or compiled input copies do not match the staged input"
```

`target` is the smart-constructor helper in
[GuideSupport.hs](../../examples/haskell-guides/GuideSupport.hs). This verifier
checks the active receipt, the completion marker, binary existence, and exact
compiled input copies. A wrapper that merely echoes the expected environment
value would not establish what its compiler built. The wrapper and verifier
are trusted cooperating code, not an attestation against a hostile build tool.

`prepareInputs` is a no-op for this content-addressed wrapper. Other providers
may need it, but it must not change selected source bytes or introduce undeclared
generated inputs. Only top-level `dist`, `dist-newstyle`, and `.heni-build` can be
retained. Use `RunOptions` based on `defaultRunOptions`, and set
`buildReuse = Just (contentAddressedReuse toolchain)`.

## Prove parity and refusal

```sh
cabal run heni:exe:heni-haskell-guides -- reuse .heni-runs/guide-reuse
```

The command executes three campaigns with distinct report directories:

| Campaign | Expected outcomes | What it checks |
| --- | --- | --- |
| `fresh` | `Caught`, `Survived`, `Caught` | Reference execution. |
| `retained` | `Caught`, `Survived`, `Caught` | Same faults/outcomes using private content-addressed artifact reuse. |
| `stale` | Three `InfrastructureError` results | Deliberately wrong active receipt is refused before candidate tests. |

The first and last candidate use identical faulty input; the retained build can
reuse its completed compiled entry. Inspect `last-candidate-build.stdout.log`
under `retained` for `content cache: hit`. Baselines remain fresh in this example;
it does not enable `ReuseBaselines`. Reports from fresh/retained campaigns are
`RunFailed` because of the intentional survivor; stale observation produces
`RunUntrustworthy`. The example executable exits 0 after verifying its expectations.

Heni independently checks staged source before/after use. Command/environment
changes discard retained artifacts; bad reset, observation failure, or unexpected
source/generated state retires the retained tree. Expected compiler rejection
also requires a valid observation when this provider is enabled. This sample
only attests successful compilations: a rejected compile writes no completion
marker, so use fresh execution for intentional compiler-rejection cases unless
your build integration can also provide a sound rejected-build observation.

The [scheduler conformance suite](../../test/scheduler/Main.hs) additionally
covers same-size/equal-mtime alternation, retiring stale trees, and verified
compiler rejection. [Scheduling contracts](scheduling.md) specify the runner's
full ownership and invalidation behavior.
