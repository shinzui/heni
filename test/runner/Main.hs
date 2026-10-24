module Main (main) where

import Control.Concurrent
import Control.Exception
import Control.Monad (forM_, unless)
import Data.ByteString qualified as BS
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Definitions (exampleCampaign)
import Paths_heni (getDataFileName)
import System.Directory qualified as Dir
import System.Environment (lookupEnv)
import System.FilePath (takeDirectory, (</>))
import System.Posix.Temp (mkdtemp)
import System.Timeout (timeout)
import Test.Heni

assert' :: String -> Bool -> IO ()
assert' name good = unless good (error name)

checked :: (Show e) => Either e a -> a
checked = either (error . show) id

main :: IO ()
main = do
  result <- timeout 180000000 suite
  assert' "outer campaign watchdog" (result == Just ())

suite :: IO ()
suite = bracket (Dir.getTemporaryDirectory >>= \tmp -> mkdtemp (tmp </> "heni-runner-test-")) Dir.removePathForcibly $ \root -> do
  fixture <- getDataFileName "examples/minimal"
  original <- BS.readFile (fixture </> "src/Capacity.hs")
  actual <- runCampaign (defaultRunOptions fixture (root </> "real")) exampleCampaign
  assert' "actual Cabal baseline/candidate classifications" (case actual of RunResult {results} -> [v | CaseResult {verdict = v} <- results] == [Caught, Survived, UnexpectedBuildFailure])
  BS.readFile (fixture </> "src/Capacity.hs") >>= assert' "actual source unchanged" . (== original)
  stored <- readReport (root </> "real/report.json")
  assert' "portable report round trip" (case stored of Right StoredReport {result} -> result == actual; _ -> False)
  schemaOutput <- lookupEnv "HENI_SCHEMA_REPORT"
  forM_ schemaOutput $ \path -> do
    Dir.createDirectoryIfMissing True (takeDirectory path)
    Dir.copyFile (root </> "real/report.json") path
  recovered <- recoverReport (root </> "real")
  assert' "journal recovery is explicitly incomplete" (case recovered of Right StoredReport {result = RunResult {status = RunUntrustworthy, results}} -> length results == 3; _ -> False)
  BS.appendFile (root </> "real/journal.jsonl") "{\"sequence\":"
  truncated <- recoverReport (root </> "real")
  assert' "truncated last record tolerated" (case truncated of Right _ -> True; _ -> False)
  Dir.renameDirectory (root </> "real") (root </> "moved")
  moved <- readReport (root </> "moved/report.json")
  assert' "moved report retains artifacts" (case moved of Right _ -> True; _ -> False)
  journal <- BS.readFile (root </> "moved/journal.jsonl")
  BS.writeFile (root </> "moved/journal.jsonl") ("garbage\n" <> journal)
  corrupt <- recoverReport (root </> "moved")
  assert' "interior corruption rejected" (case corrupt of Left _ -> True; _ -> False)
  let selectedId = checked (mkCaseId "case")
      buildId = checked (mkCommandId "build")
      testId = checked (mkCommandId "test")
      budget = checked (mkStageBudget 1000000)
      cmd args = Command "heni-fixture" args Set.empty Nothing [] budget (OutputPolicy 1024)
      source = root </> "source"
      definition = CaseDefinition selectedId "Detect the intended fixture fault" Set.empty [Replace (checked (mkRelativeTarget "input")) "anchor" "mutant" 1] buildId (Just testId) Nothing (Diagnostic Test 1 "capacity rule violated") GenericCommands
      campaign mode c hooks = checked (mkCampaign (Map.fromList [(buildId, cmd ["exit", "0"]), (testId, cmd ["check", "input", mode])]) [(c, hooks)])
  Dir.createDirectory source
  BS.writeFile (source </> "input") "anchor\n"
  forM_ [("caught", "diagnostic", Caught), ("wrong", "wrong", WrongFailure), ("timeout", "timeout", TimedOut), ("survivor", "pass", Survived)] $ \(name, mode, expected) -> do
    observed <- runCampaign (defaultRunOptions source (root </> name)) (campaign mode definition noHooks)
    assert' (name ++ " classification") (case observed of RunResult {results = [CaseResult {verdict}]} -> verdict == expected; _ -> False)
  let invalid = case definition of CaseDefinition i d ts _ b t s e mode -> CaseDefinition i d ts [Replace (checked (mkRelativeTarget "input")) "missing" "bad" 1] b t s e mode
  stale <- runCampaign (defaultRunOptions source (root </> "stale")) (campaign "diagnostic" invalid noHooks)
  assert' "invalid edit distinct" (case stale of RunResult {results = [CaseResult {verdict = InvalidMutation}]} -> True; _ -> False)
  let patch = "diff --git a/input b/input\n--- a/input\n+++ b/input\n@@ -1 +1 @@\n-anchor\n+mutant\n"
      patchedDefinition = case definition of CaseDefinition i d ts _ b t s e mode -> CaseDefinition i d ts [Patch patch] b t s e mode
  patched <- runCampaign (defaultRunOptions source (root </> "patch")) (campaign "diagnostic" patchedDefinition noHooks)
  assert' "production Git path uses supervised patch runner" (case patched of RunResult {results = [CaseResult {verdict = Caught}]} -> True; _ -> False)
  let control = case definition of CaseDefinition i d ts _ b t s _ mode -> CaseDefinition i d ts [] b t s Control mode
      failedControl = checked (mkCampaign (Map.fromList [(buildId, cmd ["exit", "0"]), (testId, cmd ["counter", root </> "control-counter"])]) [(control, noHooks)])
  controlResult <- runCampaign (defaultRunOptions source (root </> "control")) failedControl
  assert' "failed control cannot pass run" (case controlResult of RunResult {status = RunFailed, results = [CaseResult {verdict = WrongFailure}], failures = [ControlFailure {}]} -> True; _ -> False)
  BS.writeFile (source </> "input") "mutant"
  baseline <- runCampaign (defaultRunOptions source (root </> "baseline")) (campaign "diagnostic" definition noHooks)
  assert' "failed baseline prevents candidate" (case baseline of RunResult {results = [CaseResult {verdict = NotRun}], failures = [BaselineFailure {}]} -> True; _ -> False)
  BS.writeFile (source </> "input") "anchor\n"
  let failedObserver = case defaultRunOptions source (root </> "observer") of
        RunOptions s o p selected _ cleanup -> RunOptions s o p selected (\_ -> ioError (userError "observer failed")) cleanup
  observer <- runCampaign failedObserver (campaign "diagnostic" definition noHooks)
  assert' "observer failure untrustworthy" (case observer of RunResult {status = RunUntrustworthy} -> True; _ -> False)
  let named = case definition of CaseDefinition i d ts es b t s _ mode -> CaseDefinition i d ts es b t s (NamedTests (Set.singleton "intended") NoReplay) mode
  uncoveredBaseline <- runCampaign (defaultRunOptions source (root </> "empty-selection")) (campaign "diagnostic" named noHooks)
  assert' "absent named selection blocks candidate" (case uncoveredBaseline of RunResult {results = [CaseResult {verdict = NotRun}], failures = [BaselineFailure {}]} -> True; _ -> False)
  let existing = root </> "caught"
  duplicate <- try (runCampaign (defaultRunOptions source existing) (campaign "diagnostic" definition noHooks)) :: IO (Either ConfigurationFailure RunResult)
  assert' "existing output refused" (case duplicate of Left _ -> True; _ -> False)
  -- Interrupt while a real candidate command is running. Finalization preserves
  -- the active and queued case exactly once before rethrowing cancellation.
  let readyPath = root </> "candidate-ready"
  done <- newEmptyMVar
  let second = case definition of CaseDefinition _ d ts es b t s e mode -> CaseDefinition (checked (mkCaseId "queued")) d ts es b t s e mode
      commands = Map.fromList [(buildId, cmd ["exit", "0"]), (testId, cmd ["check", "input", "timeout", readyPath])]
      cancellationCampaign = checked (mkCampaign commands [(definition, noHooks), (second, noHooks)])
      cancelOptions = defaultRunOptions source (root </> "cancelled")
  tid <- forkFinally (runCampaign cancelOptions cancellationCampaign) (putMVar done)
  let waitReady = do exists <- Dir.doesFileExist readyPath; unless exists (threadDelay 5000 >> waitReady)
  waitReady
  throwTo tid ThreadKilled
  finished <- timeout 3000000 (takeMVar done)
  assert' "cancellation rethrown after finalization" (case finished of Just (Left _) -> True; _ -> False)
  partial <- readReport (root </> "cancelled/report.json")
  assert' "interrupted ledger exactly once" (case partial of Right StoredReport {result = RunResult {results, status = RunInterrupted}} -> length results == 2 && all (\CaseResult {verdict} -> verdict == NotRun) results; _ -> False)
  -- Environment values and explicitly sensitive argv are redacted in reports.
  let secretCommand = Command "heni-fixture" ["echo", "private-token"] (Set.singleton 1) Nothing [("TOKEN", "private-token")] budget (OutputPolicy 1024)
      secretCampaign = checked (mkCampaign (Map.fromList [(buildId, secretCommand), (testId, cmd ["check", "input", "diagnostic"])]) [(definition, noHooks)])
  _ <- runCampaign (defaultRunOptions source (root </> "redacted")) secretCampaign
  reportBytes <- BS.readFile (root </> "redacted/report.json")
  assert' "explicit secrets redacted in portable report" (not ("private-token" `BS.isInfixOf` reportBytes))
  cleanupCount <- newIORef (0 :: Int)
  let badCleanup = case defaultRunOptions source (root </> "cleanup-failure") of
        RunOptions s o p selected progress _ ->
          RunOptions
            s
            o
            p
            selected
            progress
            ( \_ -> do
                n <- atomicModifyIORef' cleanupCount (\n -> (n + 1, n + 1))
                if n == 2 then ioError (userError "consumer cleanup failed") else pure ()
            )
  cleanupFailed <- runCampaign badCleanup (campaign "diagnostic" definition noHooks)
  assert'
    "cleanup failure retains primary candidate evidence"
    ( case cleanupFailed of
        RunResult {status = RunUntrustworthy, results = [CaseResult {verdict = InfrastructureError, evidence = CaseEvidence {stages, cleanupErrors}}]} -> length stages == 2 && not (null cleanupErrors)
        _ -> False
    )
  -- A syntactically complete bad record is corruption, not a truncated suffix.
  originalJournal <- BS.readFile (root </> "caught/journal.jsonl")
  BS.appendFile (root </> "caught/journal.jsonl") "null"
  badLast <- recoverReport (root </> "caught")
  assert' "complete invalid final journal record rejected" (case badLast of Left _ -> True; _ -> False)
  BS.writeFile (root </> "caught/journal.jsonl") originalJournal
  Dir.removeFile (root </> "caught/case-baseline-test.stdout.log")
  missingArtifact <- readReport (root </> "caught/report.json")
  assert' "missing baseline artifact is rejected" (case missingArtifact of Left _ -> True; _ -> False)
  -- Failed final writes still return infrastructure information in memory.
  let sabotage = case defaultRunOptions source (root </> "unwritable") of
        RunOptions s o p selected _ cleanup -> RunOptions s o p selected (\case CaseFinished {} -> Dir.removePathForcibly o >> BS.writeFile o "blocks report directory"; _ -> pure ()) cleanup
  diskFailure <- runCampaign sabotage (campaign "diagnostic" definition noHooks)
  assert' "report IO failure outranks caught case" (case diskFailure of RunResult {status = RunUntrustworthy} -> True; _ -> False)
  putStrLn "Real Cabal mutation cycle, lifecycle, portable reports and recovery checks passed"
