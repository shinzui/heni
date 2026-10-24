module Main (main) where

import Control.Concurrent
import Control.Exception
import Control.Monad (unless)
import Data.ByteString qualified as BS
import Data.IORef
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Encoding
import System.Directory qualified as Dir
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.FilePath ((</>))
import System.Posix.Files (setFileTimes)
import System.Posix.Temp (mkdtemp)
import System.Timeout (timeout)
import Test.Heni
import Test.Heni.BuildReuse qualified as Build
import Test.Heni.Resource qualified as R
import Test.Heni.Scheduler (runScheduled)
import Test.Heni.Workspace

assert' :: String -> Bool -> IO ()
assert' why good = unless good (error why)

checked :: (Show e) => Either e a -> a
checked = either (error . show) id

modify_ :: IORef a -> (a -> a) -> IO ()
modify_ ref f = atomicModifyIORef' ref (\a -> (f a, ()))

main :: IO ()
main = timeout 120000000 checks >>= \case Nothing -> error "scheduler watchdog"; Just () -> pure ()

checks :: IO ()
checks = bracket (Dir.getTemporaryDirectory >>= \p -> mkdtemp (p </> "heni-scheduler-")) Dir.removePathForcibly $ \root -> do
  let source = root </> "source"
  Dir.createDirectory source
  writeFile (source </> "input") "anchor"
  lifecycle <- newIORef []
  let binding = R.ResourceBinding "fixture" "v1" (Just "clean-1") [("HENI_RESOURCE_DB_TOKEN", "secret-not-reportable")]
      makeProvider name scope failAcquire failRelease =
        R.managedResource
          name
          scope
          (if name == "WORKER" then 2 else 1)
          (\_ -> do modify_ lifecycle (++ [name <> "+"]); if failAcquire then ioError (userError "setup") else pure ((), if name == "DB" then binding else R.ResourceBinding "other" "v1" (Just "clean-1") []))
          (\() -> modify_ lifecycle (++ [name <> "="]) >> pure (if name == "DB" then binding else R.ResourceBinding "other" "v1" (Just "clean-1") []))
          (\() -> do modify_ lifecycle (++ [name <> "-"]); if failRelease then ioError (userError "cleanup") else pure ())
      db = makeProvider "DB" R.CaseScope False False
  withSnapshot source defaultSnapshotPolicy $ \snapshot -> do
    let context = R.ResourceContext "test" snapshot root (const (pure ()))
    R.withResources [db, makeProvider "SECOND" R.CaseScope False False] context $ \leases -> mapM_ (R.prepareResource . snd) leases
    events <- readIORef lifecycle
    assert' "declaration acquisition/reverse release" (events == ["DB+", "SECOND+", "DB=", "SECOND=", "SECOND-", "DB-"])
    writeIORef lifecycle []
    partial <- try (R.withResources [db, makeProvider "SECOND" R.CaseScope True False] context (const (pure ()))) :: IO (Either R.ResourceError ())
    assert' "partial acquisition reports setup" (case partial of Left _ -> True; _ -> False)
    events' <- readIORef lifecycle
    assert' "partial acquisition releases earlier ownership" (events' == ["DB+", "SECOND+", "DB-"])
    both <- try (R.withResources [makeProvider "DB" R.CaseScope False True] context (const (ioError (userError "primary")))) :: IO (Either WorkspaceFinalizationError ())
    assert' "primary plus cleanup errors preserved" (case both of Left (WorkspaceFinalizationError (Just _) _) -> True; _ -> False)
  withSnapshot source defaultSnapshotPolicy $ \snapshot -> do
    writeIORef lifecycle []
    timed <- timeout 10000 (R.withResources [db] (R.ResourceContext "timed" snapshot root (const (pure ()))) (const (threadDelay 1000000)))
    releasedAfterTimeout <- readIORef lifecycle
    assert' "timeout releases acquired callback resources" (timed == Nothing && releasedAfterTimeout == ["DB+", "DB-"])
  usage <- newIORef (0 :: Int, 0 :: Int)
  completed <- newIORef []
  let doWork _ item = bracket_ (modify_ usage (\(n, peak) -> (n + 1, max peak (n + 1)))) (modify_ usage (\(n, peak) -> (n - 1, peak))) (threadDelay 30000 >> modify_ completed (++ [item]))
  runScheduled 3 (Map.fromList [("A", 1), ("B", 1)]) [(1 :: Int, ["A", "B"]), (2, ["B", "A"]), (3, ["A"])] (\_ action -> action) doWork
  (_, peak) <- readIORef usage
  assert' "atomic opposite-order claims never overlap" (peak == 1)
  done <- readIORef completed
  assert' "finite queue completes exactly once" (sort done == [1, 2, 3])
  entered <- newMVar (0 :: Int)
  barrier <- newEmptyMVar
  runScheduled
    2
    Map.empty
    [(1 :: Int, []), (2, [])]
    (\_ action -> action)
    ( \_ _ -> do
        n <- modifyMVar entered (\v -> pure (v + 1, v + 1))
        if n == 2 then putMVar barrier () else pure ()
        readMVar barrier
    )
  let bid = checked (mkCommandId "build")
      tid = checked (mkCommandId "test")
      ids = map (checked . mkCaseId) ["first", "second", "queued"]
      command args = Command "heni-fixture" args Set.empty Nothing [] (checked (mkStageBudget 5000000)) (OutputPolicy 1024)
      definition cid = CaseDefinition cid "resource scheduling" Set.empty [Replace (checked (mkRelativeTarget "input")) "anchor" "mutant" 1] bid (Just tid) Nothing (Diagnostic Test 1 "capacity rule violated") GenericCommands
      campaign = checked (mkCampaign (Map.fromList [(bid, command ["exit", "0"]), (tid, command ["check", "input", "diagnostic"])]) [(definition cid, noHooks) | cid <- ids])
      claims = Map.fromList [(cid, ["DB"]) | cid <- ids]
  paths <- newIORef []
  let options name workers =
        (defaultRunOptions source (root </> name))
          { workers = workers,
            resources = [db],
            resourceClaims = claims,
            workspaceCleanup = \workspace -> modify_ paths (++ [workspaceRoot workspace])
          }
  serial <- runCampaign (options "serial" 1) campaign
  parallel <- runCampaign (options "parallel" 3) campaign
  let outcomes RunResult {results} = map (\CaseResult {caseId, verdict} -> (caseId, verdict)) results
  assert' "serial/parallel verdict and ledger parity" (outcomes serial == outcomes parallel && all ((== Caught) . snd) (outcomes parallel))
  roots <- readIORef paths
  assert' "all baseline/candidate trees are exclusive" (length roots == 12 && Set.size (Set.fromList roots) == 12)
  portable <- readReport (root </> "parallel/report.json")
  assert' "parallel journal/report artifacts remain readable" (case portable of Right _ -> True; _ -> False)
  writeIORef lifecycle []
  let scopedProviders = [makeProvider "DB" R.CampaignScope False False, makeProvider "WORKER" R.WorkerScope False False, makeProvider "CASE" R.CaseScope False False]
  _ <- runCampaign ((options "all-scopes" 2) {resources = scopedProviders, resourceClaims = Map.fromList [(cid, ["DB", "WORKER", "CASE"]) | cid <- ids]}) campaign
  scopeEvents <- readIORef lifecycle
  let occurrences event = length (filter (== event) scopeEvents)
  assert' ("campaign/worker/case acquire and release lifetimes: " ++ show scopeEvents) (occurrences "DB+" == 1 && occurrences "DB-" == 1 && occurrences "WORKER+" == 2 && occurrences "WORKER-" == 2 && occurrences "CASE+" == 3 && occurrences "CASE-" == 3)
  writeIORef lifecycle []
  _ <- runCampaign ((options "worker-acquisition-capacity" 3) {resources = [makeProvider "DB" R.WorkerScope False False]}) campaign
  workerEvents <- readIORef lifecycle
  assert' "worker acquisition itself respects declared capacity" (length (filter (== "DB+") workerEvents) == 1 && length (filter (== "DB-") workerEvents) == 1)
  baselineCount <- newIORef (0 :: Int)
  let observeBaseline (StageFinished _ "baseline" StageEvidence {stage = Test}) = modify_ baselineCount (+ 1)
      observeBaseline _ = pure ()
      reuseOptions name provider count = (options name count) {resources = [provider], reusePolicy = ReuseBaselines "fixture-toolchain/v1" Nothing, progress = observeBaseline}
      runCount name provider count chosen = do
        writeIORef baselineCount 0
        result <- runCampaign (reuseOptions name provider count) chosen
        invocations <- readIORef baselineCount
        pure (result, invocations)
  (reused, count) <- runCount "reuse" db 3 campaign
  assert' "compatible baselines execute exactly once across workers" (count == 1 && outcomes reused == outcomes parallel)
  originalReuseReport <- BS.readFile (root </> "reuse/report.json")
  BS.writeFile (root </> "reuse/report.json") (Encoding.encodeUtf8 (Text.replace "\"ownerCase\":\"first\"" "\"ownerCase\":\"absent\"" (Encoding.decodeUtf8 originalReuseReport)))
  badOwner <- readReport (root </> "reuse/report.json")
  assert' "reuse provenance cannot reference absent producer evidence" (case badOwner of Left _ -> True; _ -> False)
  BS.writeFile (root </> "reuse/report.json") originalReuseReport
  let bid2 = checked (mkCommandId "different-build")
      alter cid select buildId = case definition cid of CaseDefinition i d ts es _ t _ e mode -> CaseDefinition i d ts es buildId t select e mode
      varied =
        checked
          ( mkCampaign
              (Map.fromList [(bid, command ["exit", "0"]), (bid2, command ["echo", "different build option"]), (tid, command ["check", "input", "diagnostic"])])
              [(alter (ids !! 0) Nothing bid, noHooks), (alter (ids !! 1) (Just "different selection") bid, noHooks), (alter (ids !! 2) Nothing bid2, noHooks)]
          )
  (_, differentCount) <- runCount "different-contracts" db 1 varied
  assert' "selector and command/build changes invalidate sharing" (differentCount == 3)
  let unknown = R.managedResource "DB" R.CaseScope 1 (\_ -> pure ((), R.ResourceBinding "fixture" "v1" Nothing [])) (\() -> pure (R.ResourceBinding "fixture" "v1" Nothing [])) (\() -> pure ())
  (_, unknownCount) <- runCount "unknown-epoch" unknown 2 campaign
  assert' "unknown external state disables reuse" (unknownCount == 3)
  epochCounter <- newIORef (0 :: Int)
  let changing =
        R.managedResource
          "DB"
          R.CaseScope
          1
          ( \_ -> do
              n <- atomicModifyIORef' epochCounter (\v -> (v + 1, v + 1))
              let b = R.ResourceBinding "fixture" "v1" (Just (Text.pack (show n))) []
              pure (b, b)
          )
          pure
          (const (pure ()))
  (_, epochCount) <- runCount "changed-epoch" changing 1 campaign
  assert' "changed resource epoch invalidates sharing" (epochCount == 3)
  cleanupCount <- newIORef (0 :: Int)
  writeIORef baselineCount 0
  resetFailed <-
    runCampaign
      ( (reuseOptions "cleanup-invalidates" db 1)
          { workspaceCleanup = \_ -> do
              n <- atomicModifyIORef' cleanupCount (\v -> (v + 1, v + 1)); if n == 2 then ioError (userError "failed reset") else pure ()
          }
      )
      campaign
  afterFailure <- readIORef baselineCount
  assert' "failed cleanup retires cached evidence; next case is fresh" (afterFailure == 2 && case resetFailed of RunResult {results = CaseResult {verdict = InfrastructureError} : CaseResult {verdict = Caught} : _} -> True; _ -> False)
  secretReport <- BS.readFile (root </> "reuse/report.json")
  assert' "resource values and secret comparison never enter reports" (not ("secret-not-reportable" `BS.isInfixOf` secretReport))
  finishedEvents <- newIORef []
  let brokenTeardown = makeProvider "DB" R.CaseScope False True
      observeFinished (CaseFinished CaseResult {caseId, verdict}) = modify_ finishedEvents (++ [(caseId, verdict)])
      observeFinished _ = pure ()
  releasedRun <- runCampaign ((options "final-event-after-release" 2) {resources = [brokenTeardown], progress = observeFinished}) campaign
  finalEvents <- readIORef finishedEvents
  assert' "one final progress event after failing case teardown" (sort finalEvents == sort (outcomes releasedRun) && length finalEvents == 3 && all ((== InfrastructureError) . snd) finalEvents)
  priorEnv <- lookupEnv "HENI_ENV_CONFORMANCE"
  let restoreEnv = maybe (unsetEnv "HENI_ENV_CONFORMANCE") (setEnv "HENI_ENV_CONFORMANCE") priorEnv
  ( do
      setEnv "HENI_ENV_CONFORMANCE" "first-state"
      writeIORef baselineCount 0
      let envObserver event = do
            observeBaseline event
            case event of CaseFinished {} -> setEnv "HENI_ENV_CONFORMANCE" "second-state"; _ -> pure ()
      _ <- runCampaign ((reuseOptions "environment-change" db 1) {progress = envObserver}) campaign
      envCount <- readIORef baselineCount
      assert' "inherited environment contract is compared in memory" (envCount == 2)
    )
    `finally` restoreEnv
  writeFile (source </> "changed-test-or-fixture") "changed input"
  (_, newRunCount) <- runCount "new-snapshot" db 1 campaign
  assert' "a new campaign with changed inputs starts without a verdict cache" (newRunCount == 1)
  Dir.removeFile (source </> "changed-test-or-fixture")
  buildRoots <- newIORef []
  let buildProvider =
        Build.BuildReuse
          "content-key-fixture/v1"
          [checked (mkRelativeTarget "dist-newstyle")]
          (\workspace -> setFileTimes (workspaceRoot workspace </> "input") 0 0)
          ( \workspace expected -> do
              observed <- Text.pack <$> readFile (workspaceRoot workspace </> "dist-newstyle/observed-key")
              pure (if observed == expected then Right () else Left "build did not observe restored/mutated input key")
          )
      alternating mode =
        checked
          ( mkCampaign
              (Map.fromList [(bid, command ["incremental-build", mode]), (tid, command ["incremental-test"])])
              [(case definition cid of CaseDefinition i d ts _ b t sel e m -> CaseDefinition i d ts [Replace (checked (mkRelativeTarget "input")) "anchor" changed 1] b t sel e m, noHooks) | (cid, changed) <- zip ids ["mutant", "safe__", "mutant"]]
          )
      buildOptions name provider = (defaultRunOptions source (root </> name)) {buildReuse = Just provider, workspaceCleanup = \workspace -> modify_ buildRoots (++ [workspaceRoot workspace])}
  incremental <- runCampaign (buildOptions "incremental" buildProvider) (alternating "safe")
  freshAlternating <- runCampaign (defaultRunOptions source (root </> "fresh-alternating")) (alternating "safe")
  assert' "same-size alternating edits with identical coarse mtimes preserve fresh outcomes" (outcomes incremental == outcomes freshAlternating && map snd (outcomes incremental) == [Caught, Survived, Caught])
  seenRoots <- readIORef buildRoots
  assert' "one private incremental candidate tree, separate fresh baselines" (Set.size (Set.fromList seenRoots) == 4)
  unsafe <- runCampaign (buildOptions "unsafe-invalidation" buildProvider) (alternating "unsafe")
  assert' "stale build observations are infrastructure, never detection" (case unsafe of RunResult {results = [CaseResult {verdict = Caught}, CaseResult {verdict = InfrastructureError}, CaseResult {verdict = Caught}]} -> True; _ -> False)
  let rejected =
        checked
          ( mkCampaign
              (campaignCommands (alternating "reject"))
              [(case d of CaseDefinition i desc tags edits b t sel _ mode -> CaseDefinition i desc tags edits b t sel (BuildRejection 1 "intended-build-rejection") mode, noHooks) | d <- campaignCases (alternating "reject")]
          )
      badObservation = case buildProvider of Build.BuildReuse contract dirs prep _ -> Build.BuildReuse contract dirs prep (\_ _ -> pure (Left "unproved compiler input"))
  verifiedRejection <- runCampaign (buildOptions "verified-build-rejection" buildProvider) rejected
  assert' "verified retained compiler rejection keeps expected-build meaning" (map snd (outcomes verifiedRejection) == [Caught, Survived, Caught])
  rejectedBuild <- runCampaign (buildOptions "incremental-build-rejection" badObservation) rejected
  assert' "expected compiler rejection also requires observed input identity" (all ((== InfrastructureError) . snd) (outcomes rejectedBuild))
  let unexpected = case buildProvider of Build.BuildReuse contract dirs prep verify -> Build.BuildReuse contract dirs (\workspace -> prep workspace >> writeFile (workspaceRoot workspace </> "unexpected-generated") "bad") verify
  generated <- runCampaign (buildOptions "generated-input" unexpected) (alternating "safe")
  assert' "undeclared generated state invalidates retained worker" (all ((== InfrastructureError) . snd) (outcomes generated))
  acquired <- newIORef (0 :: Int)
  released <- newIORef (0 :: Int)
  ready <- newEmptyMVar
  enteredCount <- newIORef (0 :: Int)
  let held = R.managedResource "HELD" R.CaseScope 2 (\_ -> modify_ acquired (+ 1) >> pure ((), R.ResourceBinding "held" "v1" Nothing [])) (\() -> pure (R.ResourceBinding "held" "v1" Nothing [])) (\() -> modify_ released (+ 1))
      waitCampaign = checked (mkCampaign (Map.fromList [(bid, command ["sleep"]), (tid, command ["exit", "0"])]) [(definition cid, noHooks) | cid <- ids])
      observe (CaseStarted _) = do n <- atomicModifyIORef' enteredCount (\v -> (v + 1, v + 1)); if n == 2 then putMVar ready () else pure ()
      observe _ = pure ()
  finished <- newEmptyMVar
  thread <- forkFinally (runCampaign ((defaultRunOptions source (root </> "cancel")) {workers = 2, resources = [held], resourceClaims = Map.fromList [(cid, ["HELD"]) | cid <- ids], progress = observe}) waitCampaign) (putMVar finished)
  takeMVar ready
  throwTo thread ThreadKilled
  cancelled <- takeMVar finished
  let wasCancelled = case cancelled of
        Left e -> case fromException e :: Maybe AsyncException of
          Just ThreadKilled -> True
          _ -> False
        Right _ -> False
  assert' "cancellation rethrows" wasCancelled
  a <- readIORef acquired
  r <- readIORef released
  assert' "all acquired resources released on cancellation" (a == 2 && r == a)
  partialReport <- readReport (root </> "cancel/report.json")
  assert' "queued and running IDs finalized exactly once" (case partialReport of Right StoredReport {result = RunResult {results, status}} -> length results == 3 && status == RunInterrupted; _ -> False)
  putStrLn "Scoped ownership, atomic capacities, isolated workers, parity and cancellation passed"
