module Main (main) where

import Control.Exception
import Control.Monad (forM_, unless)
import Data.Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import System.Directory qualified as Dir
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory, (</>))
import System.Posix.Signals (sigABRT)
import System.Posix.Temp (mkdtemp)
import System.Timeout (timeout)
import Test.Heni
import Test.Heni.Adapter
import Test.Heni.Replay qualified as Replay

assert' :: String -> Bool -> IO ()
assert' name good = unless good (error name)

checked :: (Show e) => Either e a -> a
checked = either (error . show) id

main :: IO ()
main =
  timeout 120000000 checks >>= \case
    Nothing -> error "adapter integration watchdog"
    Just () -> pure ()

checks :: IO ()
checks = bracket (Dir.getTemporaryDirectory >>= \tmp -> mkdtemp (tmp </> "heni-adapter-test-")) Dir.removePathForcibly $ \root -> do
  let source = root </> "source"
      budget = checked (mkStageBudget 2000000)
      buildId = checked (mkCommandId "build")
      testId = checked (mkCommandId "test")
      caseId = checked (mkCaseId "named")
      command args = Command "heni-evidence-fixture" args Set.empty Nothing [] budget (OutputPolicy 1024)
      definition expectation mode = CaseDefinition caseId "Detect the intended assertion" Set.empty [Replace (checked (mkRelativeTarget "input")) "anchor" "mutant" 1] buildId (Just testId) Nothing expectation mode
      named policy = definition (NamedTests (Set.singleton "suite/intended") policy) StructuredTestsV1
      run name args chosenDefinition hooks =
        runCampaign
          (defaultRunOptions source (root </> name))
          (checked (mkCampaign (Map.fromList [(buildId, command ["exit", "0"]), (testId, command args)]) [(chosenDefinition, hooks)]))
      single verdict RunResult {results} = case results of [CaseResult {verdict = v}] -> v == verdict; _ -> False
  Dir.createDirectory source
  BS.writeFile (source </> "input") "anchor\n"
  forM_ [("intended", Caught), ("wrong", WrongFailure), ("skipped", Uncovered), ("setup", InfrastructureError), ("stale", InfrastructureError), ("partial", InfrastructureError), ("counts", InfrastructureError), ("version", InfrastructureError)] $ \(mode, expected) -> do
    result <- run mode ["protocol", "input", mode] (named NoReplay) noHooks
    unless (single expected result) $ do
      stored <- readReport (root </> mode </> "report.json")
      print (case stored of Right StoredReport {metadata = Object o} -> KM.lookup "caseDetails" o; _ -> Nothing)
    assert' ("protocol fixture " ++ mode ++ ": " ++ show result) (single expected result)
  replay <- run "replay" ["protocol", "input", "replay"] (named RequireReplay) noHooks
  assert' "required replay actual execution" (single Caught replay && case replay of RunResult {results = [CaseResult {evidence = CaseEvidence {stages}}]} -> length stages == 3; _ -> False)
  let badBuilder = CaseHooks [] Nothing (Just (\token originalCommand -> pure (Right (changeToken (Replay.replayCommand token originalCommand)))))
      changeToken (Command exe args sensitive working env changedBudget output) = Command exe args sensitive working (("HENI_REPLAY_TOKEN", "different-token") : filter ((/= "HENI_REPLAY_TOKEN") . fst) env) changedBudget output
  mismatch <- run "replay-mismatch" ["protocol", "input", "replay"] (named RequireReplay) badBuilder
  assert' "opaque token mismatch cannot be caught" (single WrongFailure mismatch)
  replayTimeout <- run "replay-timeout" ["protocol", "input", "replay-timeout"] (named RequireReplay) noHooks
  assert' ("replay timeout is a rejected reproduction with retained stage timeout: " ++ show replayTimeout) (single WrongFailure replayTimeout && case replayTimeout of RunResult {results = [CaseResult {evidence = CaseEvidence {stages}}]} -> any (\StageEvidence {stage, outcome} -> stage == Replay && outcome == Timeout) stages; _ -> False)
  let empty = case named NoReplay of CaseDefinition i d ts es b t _ e mode -> CaseDefinition i d ts es b t (Just "absent") e mode
  uncovered <- run "empty" ["protocol", "input", "intended"] empty noHooks
  assert' "known empty baseline cannot run candidate" (single NotRun uncovered)
  forM_ [("good", Caught), ("missing", WrongFailure), ("stale", WrongFailure), ("wrong-signal", WrongFailure), ("timeout", TimedOut), ("exit", WrongFailure)] $ \(mode, expected) -> do
    result <- run ("crash-" ++ mode) ["crash", "input", mode] (definition (CrashProbe (fromIntegral sigABRT) "operation-reached") GenericCommands) noHooks
    assert' ("fresh crash probe " ++ mode ++ ": " ++ show result) (single expected result)
  assert' "stable IDs escape separators unambiguously" (stableTestId ["suite/a", "x~y"] == "suite~1a/x~0y")
  -- Direct codec conformance uses an actual writer, not invented stdout.
  Dir.createDirectory (root </> "protocol")
  identity <- newRunIdentity (root </> "protocol")
  attempt <- newEvidenceAttempt (root </> "protocol") identity caseId Test "candidate"
  emitSuite attempt (SuiteEvidence "fixture/v1" (Just ["suite/intended"]) ["suite/intended"] [TestPassed "suite/intended"] [] Nothing [])
  parsed <- readEvidence attempt
  assert' "protocol round trip" (case parsed of Right (SelectionEvidence {executed = Just 1}, Nothing, "fixture/v1") -> True; _ -> False)
  schemaOutput <- lookupEnv "HENI_SCHEMA_EVIDENCE"
  forM_ schemaOutput $ \path -> Dir.createDirectoryIfMissing True (takeDirectory path) >> Dir.copyFile (evidencePath attempt) path
  duplicated <- try (emitSuite attempt (SuiteEvidence "fixture/v1" Nothing [] [] [] Nothing [])) :: IO (Either EvidenceError ())
  assert' "writer refuses stale destination" (case duplicated of Left _ -> True; _ -> False)
  invalidated <- newEvidenceAttempt (root </> "protocol") identity caseId Test "candidate"
  _ <-
    try
      ( guardEvidenceAttempt invalidated $ do
          emitSuite invalidated (SuiteEvidence "fixture/v1" Nothing ["suite/intended"] [TestFailed "suite/intended"] [] Nothing [])
          ioError (userError "cleanup after completion")
      ) ::
      IO (Either IOException ())
  bad <- readEvidence invalidated
  assert' "post-completion reporter exception invalidates proof" (case bad of Left _ -> True; _ -> False)
  putStrLn "Attempt-bound protocol, named attribution, replay and native probe checks passed"
