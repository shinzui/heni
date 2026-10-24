module Main (main) where

import Consumer
import Control.Monad (forM_, unless)
import Data.Set qualified as Set
import Data.Text qualified
import Labels (labelWorks)
import Test.Heni

assert :: String -> Bool -> IO ()
assert name condition = unless condition (error name)

buildOk :: StageEvidence
buildOk = stageEvidence Build (Exited 0) ""

stageEvidence :: Stage -> ProcessOutcome -> String -> StageEvidence
stageEvidence s o text = StageEvidence s o (fromString text) False unknownSelection Nothing 0 []
  where
    fromString = Data.Text.pack

namedFailure :: StageEvidence
namedFailure =
  StageEvidence
    Test
    (Exited 1)
    ""
    False
    (SelectionEvidence (Just 1) (Just 1) (Just 1) intended intended Set.empty [])
    Nothing
    0
    []

intended :: Set.Set Data.Text.Text
intended = Set.singleton "rejects full capacity"

observations :: [StageEvidence] -> CaseEvidence
observations ss = CaseEvidence BaselinePassed Changed ss [] [] Nothing

verdictOf :: CaseDefinition -> CaseEvidence -> Verdict
verdictOf c e = case classifyCase c e of CaseResult {verdict} -> verdict

withSelection :: SelectionEvidence -> StageEvidence -> StageEvidence
withSelection sel (StageEvidence s o txt tr _ r d logs) = StageEvidence s o txt tr sel r d logs

withReplay :: ReplayEvidence -> StageEvidence -> StageEvidence
withReplay r (StageEvidence s o txt tr sel _ d logs) = StageEvidence s o txt tr sel (Just r) d logs

main :: IO ()
main = do
  assert "own label instance" labelWorks
  forM_ definitions (\c -> assert "public construction" (validateCase c == Right ()))
  let matching = observations [buildOk, namedFailure]
      wrongNamed =
        withSelection
          ( SelectionEvidence
              (Just 2)
              (Just 2)
              (Just 2)
              (Set.insert "unrelated" intended)
              (Set.singleton "unrelated")
              Set.empty
              []
          )
          namedFailure
      extraNamed =
        withSelection
          ( SelectionEvidence
              (Just 2)
              (Just 2)
              (Just 2)
              (Set.insert "unrelated" intended)
              (Set.insert "unrelated" intended)
              Set.empty
              []
          )
          namedFailure
      zero = withSelection (SelectionEvidence (Just 1) (Just 0) (Just 0) Set.empty Set.empty intended []) namedFailure
      setup = withSelection (SelectionEvidence (Just 1) (Just 1) (Just 1) intended intended Set.empty ["fixture setup failed"]) namedFailure
      testDiag = stageEvidence Test (Exited 1) "capacity rule violated"
      baselineFailed = CaseEvidence (BaselineFailed "unchanged test failed") Changed [] [] [] Nothing
      replayInfo = ReplayEvidence "seed:42" "size=20" intended
      replayStage = withReplay replayInfo (case namedFailure of StageEvidence _ o txt tr sel r d logs -> StageEvidence Replay o txt tr sel r d logs)
      replayMismatch = withReplay (ReplayEvidence "seed:43" "size=20" intended) replayStage
      scenarios =
        [ ("correct named failure", namedCase, matching, Caught),
          ("wrong named failure", namedCase, observations [buildOk, wrongNamed], WrongFailure),
          ("extra named failure", namedCase, observations [buildOk, extraNamed], WrongFailure),
          ("wrong exit", diagnosticCase, observations [buildOk, stageEvidence Test (Exited 2) "capacity rule violated"], WrongFailure),
          ("diagnostic before timeout", diagnosticCase, observations [buildOk, stageEvidence Test Timeout "capacity rule violated"], TimedOut),
          ("zero tests", namedCase, observations [buildOk, zero], Uncovered),
          ("unknown counts", namedCase, observations [buildOk, testDiag], Uncovered),
          ("skipped intended test", namedCase, observations [buildOk, zero], Uncovered),
          ("semantic compile failure", namedCase, observations [stageEvidence Build (Exited 1) "compile error"], UnexpectedBuildFailure),
          ("intentional compile rejection", buildCase, observations [stageEvidence Build (Exited 1) "unbound variable"], Caught),
          ("unrelated compile rejection", buildCase, observations [stageEvidence Build (Exited 1) "missing package"], WrongFailure),
          ("stale edit", namedCase, CaseEvidence BaselinePassed (EditRejected "anchor missing") [] [] [] Nothing, InvalidMutation),
          ("no-op edit", namedCase, CaseEvidence BaselinePassed Unchanged [] [] [] Nothing, InvalidMutation),
          ("baseline failure", namedCase, baselineFailed, NotRun),
          ("setup failure with named witness", namedCase, observations [buildOk, setup], InfrastructureError),
          ("cleanup failure with named witness", namedCase, CaseEvidence BaselinePassed Changed [buildOk, namedFailure] [] ["reset failed"] Nothing, InfrastructureError),
          ("crash without probe", crashCase, observations [buildOk, stageEvidence Test (Signaled 6) ""], WrongFailure),
          ("crash with probe", crashCase, observations [buildOk, stageEvidence Test (Signaled 6) "capacity-probe: native operation reached"], Caught),
          ("runner kill cannot be crash", crashCase, observations [buildOk, stageEvidence Test Timeout "capacity-probe: native operation reached"], TimedOut),
          ("missing replay", replayCase, matching, WrongFailure),
          ("matching replay", replayCase, observations [buildOk, withReplay replayInfo namedFailure, replayStage], Caught),
          ("replay identity mismatch", replayCase, observations [buildOk, withReplay replayInfo namedFailure, replayMismatch], WrongFailure),
          ("duplicate stage", namedCase, observations [buildOk, namedFailure, namedFailure], InfrastructureError),
          ("diagnostic detection", diagnosticCase, observations [buildOk, testDiag], Caught),
          ("survivor", diagnosticCase, observations [buildOk, stageEvidence Test (Exited 0) ""], Survived),
          ("passing control", controlCase, CaseEvidence BaselinePassed Unchanged [buildOk, stageEvidence Test (Exited 0) ""] [] [] Nothing, Caught),
          ("failing control", controlCase, CaseEvidence BaselinePassed Unchanged [buildOk, testDiag] [] [] Nothing, WrongFailure),
          ("truncated witness", diagnosticCase, observations [buildOk, StageEvidence Test (Exited 1) "capacity rule violated" True unknownSelection Nothing 0 []], InfrastructureError)
        ]
  forM_ scenarios $ \(name, c, e, expected) -> assert (name ++ ": " ++ show (classifyCase c e)) (verdictOf c e == expected)
  let checked = either (error . show) id
      i = case namedCase of CaseDefinition {caseId} -> caseId
      selected = checked (mkSelectedCases [i])
      result = classifyCase namedCase matching
      summary = checked (summarizeRun selected [result] [])
  assert "duplicate results rejected" (case summarizeRun selected [result, result] [] of Left _ -> True; _ -> False)
  assert "missing result accounted" (case checked (summarizeRun selected [] []) of RunResult {results = [CaseResult {verdict = NotRun}]} -> True; _ -> False)
  assert "single semantic score" (case summary of RunResult {score = Just (SemanticScore 1 1 True), status = RunPassed} -> True; _ -> False)
  assert "baseline becomes run failure" (case checked (summarizeRun selected [classifyCase namedCase baselineFailed] []) of RunResult {failures = [BaselineFailure {}], status = RunFailed} -> True; _ -> False)
  assert "control becomes run failure" (case checked (summarizeRun selected [classifyCase controlCase (CaseEvidence BaselinePassed Unchanged [buildOk, testDiag] [] [] Nothing)] []) of RunResult {failures = [ControlFailure {}]} -> True; _ -> False)
  assert "zero denominator" (case checked (summarizeRun selected [classifyCase buildCase (observations [stageEvidence Build (Exited 1) "unbound variable"])] []) of RunResult {score = Nothing} -> True; _ -> False)
  assert "infrastructure precedence" (case checked (summarizeRun selected [classifyCase diagnosticCase (observations [buildOk, stageEvidence Test (Exited 0) ""])] [RunInfrastructure "report failed"]) of RunResult {status = RunUntrustworthy} -> True; _ -> False)
  forM_ ["", "/absolute", "../escape", "a/../b", "a//b", "C:drive", "a\\b", "a/./b"] $ \p ->
    assert ("reject path " ++ p) (case mkRelativeTarget p of Left _ -> True; _ -> False)
  assert "budget zero rejected" (case mkStageBudget 0 of Left _ -> True; _ -> False)
  assert "empty selection rejected" (case mkSelectedCases [] of Left _ -> True; _ -> False)
  assert "duplicate selection rejected" (case mkSelectedCases [i, i] of Left _ -> True; _ -> False)
  -- Every permutation of unique stage evidence classifies identically; duplication
  -- is a protocol error rather than an inflated count.
  assert "stage reordering" (verdictOf namedCase (observations [namedFailure, buildOk]) == Caught)
  putStrLn (show (length scenarios) ++ " classifier scenarios and ledger/API invariants passed")
