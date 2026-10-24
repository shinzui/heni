-- | Pure evidence classification and exactly-once campaign accounting.
module Test.Heni.Result
  ( MutationEvidence (..),
    BaselineEvidence (..),
    CaseEvidence (..),
    Verdict (..),
    DetectionKind (..),
    CaseResult (..),
    RunFailure (..),
    RunStatus (..),
    SemanticScore (..),
    RunResult (..),
    classifyCase,
    summarizeRun,
  )
where

import Data.List (find, nub)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Test.Heni.Case (validateCase)
import Test.Heni.Internal.Model

-- | Classify observations without running IO. Validity gates precede all witnesses.
classifyCase :: CaseDefinition -> CaseEvidence -> CaseResult
classifyCase definition@CaseDefinition {caseId, expectation} evidence@CaseEvidence {baseline, mutation, stages, infrastructureErrors, cleanupErrors, stopped}
  | Left err <- validateCase definition = result InfrastructureError Nothing (Text.pack (show err))
  | not (null infrastructureErrors && null cleanupErrors) = result InfrastructureError Nothing "infrastructure or cleanup failed"
  | any stageInfrastructure stages = result InfrastructureError Nothing "launch, setup, output, or evidence protocol failed"
  | length stages /= Set.size (Set.fromList [s | StageEvidence {stage = s} <- stages]) = result InfrastructureError Nothing "duplicate stage evidence"
  | Just why <- stopped = result NotRun Nothing why
  | baseline /= BaselinePassed = result NotRun Nothing "unchanged baseline did not pass"
  | EditRejected why <- mutation = result InvalidMutation Nothing why
  | expectation /= Control && mutation /= Changed = result InvalidMutation Nothing "mutation did not change bytes"
  | expectation == Control && mutation /= Unchanged = result InvalidMutation Nothing "control changed bytes"
  | any (\StageEvidence {outcome} -> outcome == Timeout) stages = result TimedOut Nothing "stage exceeded wall-clock budget"
  | any (\StageEvidence {outcome} -> outcome == Cancelled) stages = result NotRun Nothing "stage cancelled"
  | otherwise = classifyExpectation expectation
  where
    semanticCase = case expectation of
      NamedTests {} -> True
      Diagnostic Test _ _ -> True
      _ -> False
    result v d r = CaseResult caseId v d semanticCase (expectation == Control) r evidence
    at s = find (\StageEvidence {stage} -> stage == s) stages
    passed s = case at s of Just StageEvidence {outcome = Exited 0} -> True; _ -> False
    buildGate next
      | at Build == Nothing = result InfrastructureError Nothing "missing build evidence"
      | not (passed Build) = result UnexpectedBuildFailure Nothing "semantic candidate did not build"
      | otherwise = next
    missing = result InfrastructureError Nothing "missing required stage evidence"
    wrong = result WrongFailure Nothing "observed failure did not match the declared expectation"
    survived = result Survived Nothing "candidate passed without the required detection"
    caught kind = result Caught (Just kind) "declared failure and witness matched"
    diagnostic s code witness kind = case at s of
      Nothing -> missing
      Just StageEvidence {outcome, transcript}
        | outcome == Exited code && witness `Text.isInfixOf` transcript -> caught kind
        | outcome == Exited 0 -> survived
        | otherwise -> wrong
    classifyExpectation (Diagnostic Build code witness) = diagnostic Build code witness ExpectedBuildRejection
    classifyExpectation (Diagnostic s code witness) = buildGate (diagnostic s code witness GenericDiagnostic)
    classifyExpectation (BuildRejection code witness) = diagnostic Build code witness ExpectedBuildRejection
    classifyExpectation (CrashProbe sig probe) = buildGate $ case at Test of
      Nothing -> missing
      Just StageEvidence {outcome, transcript}
        | outcome == Signaled sig && probe `Text.isInfixOf` transcript -> caught ExplicitCrash
        | outcome == Exited 0 -> survived
        | otherwise -> wrong
    classifyExpectation Control = buildGate $ case at Test of
      Nothing -> missing
      Just StageEvidence {outcome = Exited 0} -> result Caught (Just ControlPassed) "unchanged control passed"
      _ -> wrong
    classifyExpectation (NamedTests expected policy) = buildGate $ case at Test of
      Nothing -> missing
      Just original@StageEvidence {outcome, selection = SelectionEvidence {selected, executed, executedIds, failedIds, skippedIds}}
        | maybe True (<= 0) selected || maybe True (<= 0) executed || not (expected `Set.isSubsetOf` executedIds) || not (Set.null (Set.intersection expected skippedIds)) -> result Uncovered Nothing "intended tests did not execute"
        | outcome == Exited 0 && Set.null failedIds -> survived
        | outcome == Exited 0 || outcome /= Exited 1 || failedIds /= expected -> wrong
        | policy == RequireReplay && not (reproduced expected original) -> result WrongFailure Nothing "required replay did not reproduce identical failure and generator identity"
        | otherwise -> caught SemanticNamed
    reproduced expected StageEvidence {replay = Just ReplayEvidence {token = t, generator = g, failures = fs}} =
      not (Text.null t || Text.null g) && fs == expected && case at Replay of
        Just StageEvidence {outcome = Exited 1, selection = SelectionEvidence {executed, executedIds, failedIds, skippedIds}, replay = Just ReplayEvidence {token = rt, generator = rg, failures = rfs}} ->
          maybe False (> 0) executed && expected `Set.isSubsetOf` executedIds && Set.null (Set.intersection expected skippedIds) && failedIds == expected && rfs == expected && rt == t && rg == g
        _ -> False
    reproduced _ _ = False

stageInfrastructure :: StageEvidence -> Bool
stageInfrastructure StageEvidence {stage, outcome, truncated, selection = SelectionEvidence {discovered, selected, executed, executedIds, failedIds, skippedIds, setupErrors}} =
  launchFailure || hookFailure || truncated || not (null setupErrors) || invalidCounts || invalidIds
  where
    launchFailure = case outcome of LaunchFailed {} -> True; _ -> False
    hookFailure = stage `elem` [Setup, Teardown] && outcome `notElem` [Exited 0, Timeout, Cancelled]
    invalidCounts =
      any (maybe False (< 0)) [discovered, selected, executed]
        || exceeds selected discovered
        || exceeds executed selected
        || maybe False (< Set.size executedIds) executed
    exceeds (Just a) (Just b) = a > b
    exceeds _ _ = False
    invalidIds = not (failedIds `Set.isSubsetOf` executedIds) || not (Set.null (Set.intersection executedIds skippedIds))

-- | Reject duplicate/foreign results, fill missing results with 'NotRun', and
-- recompute totals from the selected ledger. Input ordering cannot inflate scores.
summarizeRun :: SelectedCases -> [CaseResult] -> [RunFailure] -> Either ConfigError RunResult
summarizeRun (SelectedCases ids) supplied suppliedFailures
  | length supplied /= Map.size byId = bad "duplicate case result"
  | any (`notElem` ids) (Map.keys byId) = bad "result for unselected case"
  | any (`notElem` ids) affected = bad "run failure refers to unselected case"
  | otherwise = Right (RunResult ids ordered allFailures runStatus semanticScore)
  where
    bad = Left . ConfigError "results"
    byId = Map.fromList [(i, r) | r@CaseResult {caseId = i} <- supplied]
    missing i = CaseResult i NotRun Nothing False False "selected case did not complete" (CaseEvidence BaselineUnavailable Unchanged [] [] [] (Just "not executed"))
    ordered = [Map.findWithDefault (missing i) i byId | i <- ids]
    controlFailures = [ControlFailure i why | CaseResult {caseId = i, verdict, reason = why, control = True} <- ordered, verdict /= Caught]
    baselineFailures = [BaselineFailure [i] why | CaseResult {caseId = i, evidence = CaseEvidence {baseline = BaselineFailed why}} <- ordered]
    allFailures = nub (suppliedFailures ++ controlFailures ++ baselineFailures)
    affected = concatMap (\case BaselineFailure xs _ -> xs; ControlFailure i _ -> [i]; _ -> []) suppliedFailures
    hasInfra = any (\CaseResult {verdict} -> verdict == InfrastructureError) ordered || any (\case RunInfrastructure {} -> True; _ -> False) allFailures
    interrupted = any (\case Interrupted {} -> True; _ -> False) allFailures
    runStatus
      | hasInfra = RunUntrustworthy
      | interrupted = RunInterrupted
      | not (null allFailures) || any (\CaseResult {verdict} -> verdict /= Caught) ordered = RunFailed
      | otherwise = RunPassed
    numerator = length [() | CaseResult {semantic = True, verdict = Caught} <- ordered]
    denominator = numerator + length [() | CaseResult {semantic = True, verdict = Survived} <- ordered]
    isComplete = null allFailures && all (\CaseResult {verdict} -> verdict `elem` [Caught, Survived]) ordered
    semanticScore = if denominator == 0 then Nothing else Just (SemanticScore numerator denominator isComplete)
