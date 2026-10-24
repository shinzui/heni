---
type: Guide
title: "Write controls and expected compiler rejection in Haskell"
description: "Run unchanged controls and real compiler rejection without confusing them with semantic detection."
docId: DOC-20
tags: ["haskell", "controls", "compiler", "expectations"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T23:15:20Z
sources:
  - resource: examples/haskell-guides/GuideCases.hs
  - resource: src/Test/Heni/Case.hs
  - resource: src/Test/Heni/Result.hs
---

# Write controls and expected compiler rejection in Haskell

Use `Control` to prove unchanged behavior, `BuildRejection` when the intended
fault should be rejected by the compiler, and `Diagnostic Test` or `NamedTests`
when a successfully built candidate must fail a test. Pick the expectation before
execution; a compiler error during a semantic case is a failed contract.

The [compiled example](../../examples/haskell-guides/GuideCases.hs) uses qualified
`Test.Heni` names and the helpers in
[GuideSupport.hs](../../examples/haskell-guides/GuideSupport.hs). Its build command
compiles a real Haskell module and capacity checker with GHC:

```haskell
runExpectations :: FilePath -> FilePath -> FilePath -> FilePath -> IO ()
runExpectations self ghc source output = do
  let rejected = H.Replace (target "Subject.hs") "used < limit" "missingCapacityGuard" 1
      control = definition "unchanged" [] H.Control
      compiler = (definition "expected-rejection" [rejected] (H.BuildRejection 1 "missingCapacityGuard")) {H.test = Nothing}
      semantic = definition "unrelated-build-error" [rejected] diagnostic
      cases = [(control, H.noHooks), (compiler, H.noHooks), (semantic, H.noHooks)]
  result <- H.runCampaign (H.defaultRunOptions source output) (campaign (commands self ghc "normal") cases)
  expectVerdicts [H.Caught, H.Caught, H.UnexpectedBuildFailure] result
  let H.RunResult {H.results, H.status, H.score} = result
      kinds = [kind | H.CaseResult {H.detection = kind} <- results]
  unless
    (kinds == [Just H.ControlPassed, Just H.ExpectedBuildRejection, Nothing] && status == H.RunFailed && score == Nothing)
    (error (show result))
```

Run it from the repository root, with a new output path:

```sh
cabal run heni:exe:heni-haskell-guides -- expectations .heni-runs/guide-expectations
```

| Case | Expected verdict | Detection kind | Why |
| --- | --- | --- | --- |
| `unchanged` | `Caught` | `ControlPassed` | No edits; unchanged build/test passes. |
| `expected-rejection` | `Caught` | `ExpectedBuildRejection` | Unchanged GHC build passes; changed build exits 1 naming `missingCapacityGuard`. |
| `unrelated-build-error` | `UnexpectedBuildFailure` | None | Same compiler error prevents a semantic assertion from running. |

The run is `RunFailed`, because the third case intentionally fails its declared
contract. The example executable exits 0 only after verifying these outcomes; it
is a teaching harness, not a production campaign exit gate. The report's score
is `Nothing`: no semantic case reached a caught/survived denominator. Passing
controls and expected compiler rejection do not inflate a semantic score.

## Choose the validity obligations

A control has `edits = []`, a build command, and a test command. Registering any
edit with `Control` is a configuration error. The baseline must pass before the
candidate control is allowed to execute; a control that fails later also adds a
run-level `ControlFailure`. Treat it as evidence that the campaign contract was
not met, even if other mutations are caught.

A `BuildRejection` case still changes source bytes and needs an unchanged passing
build. Set `test = Nothing` when rejection is the whole contract. Require a
positive compiler exit and a nonempty diagnostic precise enough to identify the
intended rejection. Timeout, launch failure, stale edits, and unrelated diagnostics
cannot satisfy it. GHC wording can change across compiler versions; use a stable
fault-specific name and validate against the supported compiler.

`Diagnostic Build code witness` has the same build-rejection detection category.
A semantic `Diagnostic Test` requires successful Build before comparing the test
exit and witness. Native signals have a [different evidence channel](crash-guide.md).
See [classification](classification.md) for precedence and
[report consumption](report-consumption-guide.md) for application gating.
