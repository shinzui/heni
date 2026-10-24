---
type: Guide
title: "Consume campaign results and reports in Haskell"
description: "Gate applications from RunResult, read validated StoredReport values, inspect evidence, and recover journals honestly."
docId: DOC-24
tags: ["haskell", "results", "reports", "json", "recovery"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T23:15:20Z
sources:
  - resource: examples/haskell-guides/GuideReports.hs
  - resource: src/Test/Heni/Report.hs
  - resource: src/Test/Heni/Result.hs
---

# Consume campaign results and reports in Haskell

Use `RunResult` returned by `runCampaign`, or load a stored report through
`readReport`. Let `RunResult.status` decide the campaign gate; case counts and a
semantic ratio alone omit baseline, control, infrastructure, and interruption
obligations. The library does not terminate the embedding application.

## Own the application gate

The compiled [GuideReports.hs](../../examples/haskell-guides/GuideReports.hs)
uses this complete status mapping:

```haskell
gateExit :: H.RunResult -> ExitCode
gateExit H.RunResult {H.status} = case status of
  H.RunPassed -> ExitSuccess
  H.RunFailed -> ExitFailure 1
  H.RunUntrustworthy -> ExitFailure 2
  H.RunInterrupted -> ExitFailure 130
```

Import `Test.Heni qualified as H` and `System.Exit (ExitCode(..), exitWith)`.
A production executable can call `exitWith (gateExit result)` after retaining or
rendering its diagnostics. The guide example instead asserts intentional outcomes
and exits successfully when its demonstrations pass; its shell exit is not the
status of those deliberately failing campaigns.

Campaign construction returns `Either ConfigError Campaign`. `runCampaign` can
throw `ConfigurationFailure` for execution preflight; handle that separately from
a returned `RunUntrustworthy`. Cancellation finalizes partial evidence and rethrows
the original asynchronous exception. A library embedding that maps SIGINT to an
exit code must own that outer exception policy; `gateExit` alone is not an async
exception handler. Do not catch all asynchronous exceptions and report success.

## Inspect typed results

Pattern-match `RunResult {results, failures, score}` and each
`CaseResult {caseId, verdict, detection, reason, evidence}`. Preserve run-level
`BaselineFailure`, `ControlFailure`, `RunInfrastructure`, and `Interrupted` values.
Every selected ID is accounted for, including `NotRun`. Keep incomplete evidence
visible rather than dropping cases that never reached a test.

| Value | Interpretation |
| --- | --- |
| `Caught` | Read `detection` to distinguish semantic/named detection, expected build rejection, explicit crash, and a passing control. |
| `Survived` | A valid candidate did not meet the required detection; not a proof of equivalence. |
| `InvalidMutation`, `Uncovered`, `UnexpectedBuildFailure`, `WrongFailure`, `TimedOut`, `InfrastructureError`, `NotRun` | Unresolved campaign obligations; inspect `reason`, stage evidence, and run failures. |
| `score = Nothing` | No semantic caught/survived denominator. |
| `Just (SemanticScore caught total complete)` | Semantic ratio plus its completeness flag; other detection kinds are excluded. |

`CaseEvidence.stages` contains the candidate's actual `StageEvidence`: `stage`,
`outcome`, `selection`, `replay`, duration, witness transcript, and relative
`logPaths`. Match `Exited`, `Signaled`, `Timeout`, `Cancelled`, and `LaunchFailed`
as distinct constructors. Generic commands keep unknown test counts as `Nothing`.
Raw-log truncation can coexist with a preserved byte-matched diagnostic witness;
consult [report contracts](reports.md) before treating a log prefix as all output.
Baseline/patch observations and resource lifecycle records live in report metadata.

The complete typed rendering function used by the example is:

```haskell
printResult :: H.RunResult -> IO ()
printResult result@H.RunResult {H.results, H.failures, H.score} = do
  putStrLn ("Campaign gate: " ++ show (gateExit result))
  mapM_
    ( \H.CaseResult {H.caseId, H.verdict, H.detection, H.reason, H.evidence = H.CaseEvidence {H.stages}} -> do
        print (H.caseIdText caseId, verdict, detection, reason)
        mapM_
          (\H.StageEvidence {H.stage, H.outcome, H.selection, H.replay, H.logPaths} -> print (stage, outcome, selection, replay, logPaths))
          stages
    )
    results
  mapM_ print failures
  case score of
    Nothing -> putStrLn "No semantic caught/survived denominator."
    Just (H.SemanticScore caught total complete) -> print (caught, total, complete)
  -- Export through the explicit wire codec, never by deriving from constructors.
  LBS.putStrLn (encode (H.runResultJSON result))
```

## Read and export stored evidence

`readReport :: FilePath -> IO (Either ReportError StoredReport)` expects the
`report.json` filename. `recoverReport` instead expects the directory containing
`journal.jsonl`. The [compiled consumer](../../examples/haskell-guides/GuideReports.hs)
uses both entry points:

```haskell
inspectReport :: FilePath -> IO ()
inspectReport path = do
  loaded <- H.readReport path
  case loaded of
    Left err -> ioError (userError ("Report could not be validated: " ++ show err))
    Right stored@H.StoredReport {H.result} -> do
      printResult result
      LBS.putStrLn (encode (H.reportJSON stored))
  recovered <- H.recoverReport (takeDirectory path)
  case recovered of
    Left err -> ioError (userError ("Journal could not be recovered: " ++ show err))
    Right H.StoredReport {H.result = result@H.RunResult {H.status}} -> do
      unless (status == H.RunUntrustworthy) (error "recovery incorrectly claimed trust")
      putStrLn ("Recovered gate: " ++ show (gateExit result))
```

`StoredReport` has `metadata :: Value` and `result :: RunResult`. Metadata remains
an Aeson value; results have the typed interface above. Use
`encode (runResultJSON result)` for the result payload or
`encode (reportJSON stored)` for the full versioned envelope. Haskell constructor
spellings and a derived generic JSON instance are not the wire format. This
example uses Aeson directly because its application chooses to export JSON.

Generate a report, then read it from Haskell:

```sh
cabal run heni:exe:heni-haskell-guides -- expectations .heni-runs/guide-report-input
cabal run heni:exe:heni-haskell-guides -- report .heni-runs/guide-report-input/report.json
```

Expect `ExitFailure 1` for the original campaign gate and `ExitFailure 2` for its
recovered snapshot. The consumer also prints typed cases/failures and explicit
JSON encodings. Its own exit is 0 when reading and its assertions succeed. Those
are diagnostic outputs, not an alternative source of campaign status.

## Keep artifact and recovery semantics

Handle `Left ReportError` as failed validation, not an empty successful run.
Readers check versions, duplicate keys, accounting, artifact containment/existence,
and symlink components. Move or archive the whole report directory with its logs;
copying only the JSON can make the referenced evidence unreadable. Resolve relative
log names from that retained directory after a successful read.

Recovery never executes commands or resumes the campaign. It tolerates only an
unfinished final journal record and rejects interior corruption or sequence gaps.
Every recovered report is `RunUntrustworthy`, including a journal whose last
snapshot showed all cases complete. Run a new campaign for a trustworthy pass.
Do not call `writeReport` to relabel recovered evidence as complete.

Environment and marked argv metadata is redacted; consumer log text and property
counterexamples retain what the program emitted. Treat those artifacts according
to the consumer's data policy. See [troubleshooting](troubleshooting.md) for each
verdict and the [report reference](reports.md) for retained field semantics.
