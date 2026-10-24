module Main (main) where

import Control.Concurrent
import Control.Exception
import Control.Monad (forM_, unless)
import Data.ByteString qualified as BS
import Data.Set qualified as Set
import Data.Text qualified as Text
import System.Directory qualified as Dir
import System.FilePath ((</>))
import System.Posix.Files (createSymbolicLink, fileExist, setFileMode)
import System.Posix.Signals
import System.Posix.Temp (mkdtemp)
import System.Posix.Types qualified
import System.Timeout (timeout)
import Test.Heni
import Test.Heni.Process
import Test.Heni.Workspace

assert' :: String -> Bool -> IO ()
assert' name good = unless good (error name)

checked :: (Show e) => Either e a -> a
checked = either (error . show) id

command :: [String] -> Int -> Command
command args micros = Command "heni-fixture" args Set.empty Nothing [] (checked (mkStageBudget micros)) (OutputPolicy 1024)

main :: IO ()
main = do
  result <- timeout 20000000 suite
  assert' "outer process-suite watchdog" (result == Just ())

suite :: IO ()
suite = bracket (Dir.getTemporaryDirectory >>= \tmp -> mkdtemp (tmp </> "heni-process-test-")) Dir.removePathForcibly $ \root -> do
  Dir.createDirectory (root </> "source")
  withSnapshot (root </> "source") defaultSnapshotPolicy $ \snapshot -> withWorkspace snapshot $ \workspace -> do
    let opts prefix = case defaultProcessOptions (root </> "logs") prefix of
          ProcessOptions d p g _ e observer -> ProcessOptions d p g ["exact-witness"] e observer
        run prefix args micros = runCommand (opts prefix) workspace Test (command args micros)
        outcomeOf ProcessReport {evidence = StageEvidence {outcome}} = outcome
    missing <- runCommand (opts "missing") workspace Test (Command "heni-definitely-absent" [] Set.empty Nothing [] (checked (mkStageBudget 100000)) (OutputPolicy 100))
    assert' "launch failure" (case outcomeOf missing of LaunchFailed {} -> True; _ -> False)
    exited <- run "exit" ["exit", "1"] 1000000
    assert' ("exit differs from signal: " ++ show (outcomeOf exited)) (outcomeOf exited == Exited 1)
    let localCommand = Command "./local-fixture" ["exit", "1"] Set.empty Nothing [] (checked (mkStageBudget 2000000)) (OutputPolicy 1024)
    deferred <- validateExecutable localCommand
    assert' "workspace executable availability is deferred until build" (deferred == Right ())
    installed <- Dir.findExecutable "heni-fixture" >>= maybe (error "missing fixture") pure
    Dir.copyFile installed (workspaceRoot workspace </> "local-fixture")
    setFileMode (workspaceRoot workspace </> "local-fixture") 0o700
    local <- runCommand (opts "workspace-program") workspace Test localCommand
    assert' "built workspace executable runs from owned tree" (outcomeOf local == Exited 1)
    assert' "workspace executable traversal is invalid" (case validateCommand (Command "./../escape" [] Set.empty Nothing [] (checked (mkStageBudget 100000)) (OutputPolicy 100)) of Left _ -> True; _ -> False)
    Dir.removeFile (workspaceRoot workspace </> "local-fixture")
    createSymbolicLink installed (workspaceRoot workspace </> "local-fixture")
    escaped <- runCommand (opts "workspace-symlink") workspace Test localCommand
    assert' "workspace executable symlinks are rejected before launch" (case outcomeOf escaped of LaunchFailed {} -> True; _ -> False)
    Dir.removeFile (workspaceRoot workspace </> "local-fixture")
    signaled <- run "signal" ["signal"] 1000000
    assert' "actual signal" (outcomeOf signaled == Signaled (fromIntegral sigABRT))
    timed <- run "timeout" ["sleep"] 50000
    assert' "witness before timeout" (outcomeOf timed == Timeout)
    assert' "bounded timeout and cleanup" (case timed of ProcessReport {evidence = StageEvidence {durationSeconds}} -> durationSeconds < 2)
    forM_ [1 .. 12 :: Int] $ \n -> do
      repeated <- run ("timeout-race-" ++ show n) ["sleep"] 20000
      assert' ("repeated group disappearance retains clean timeout: " ++ show repeated) (outcomeOf repeated == Timeout && case repeated of ProcessReport {errors} -> null errors)
    literal <- run "literal" ["echo", "space word", "'quotes'", "$HOME", "; touch nope"] 1000000
    assert' "literal argument command succeeds" (outcomeOf literal == Exited 0)
    bytes <- BS.readFile (root </> "logs/literal.stdout.log")
    assert' "arguments preserved literally" (all (`BS.isInfixOf` bytes) ["space word", "'quotes'", "$HOME", "; touch nope"])
    noFile <- fileExist (workspaceRoot workspace </> "nope")
    assert' "no shell interpolation" (not noFile)
    flood <- run "flood" ["flood"] 5000000
    assert' "concurrent drains complete" (outcomeOf flood == Exited 1)
    assert' "witness retained beyond log cap and chunk boundary" (case flood of ProcessReport {preservedWitnesses, logs, evidence = StageEvidence {truncated}} -> preservedWitnesses == ["exact-witness"] && not truncated && all (\LogArtifact {bytesRetained} -> bytesRetained <= 1024) logs && any (\LogArtifact {truncated = t} -> t) logs)
    malformed <- runCommand (case opts "invalid" of ProcessOptions d p g _ e o -> ProcessOptions d p g ["\xfffd"] e o) workspace Test (command ["invalid-utf8"] 1000000)
    assert' "invalid UTF8 cannot fabricate witness" (case malformed of ProcessReport {preservedWitnesses, evidence = StageEvidence {transcript}} -> null preservedWitnesses && Text.null transcript)
    let marker = root </> "descendant.pid"
    descendants <- run "descendant" ["descendant", marker] 2000000
    pid <- read <$> readFile marker
    assert' "leader normal exit preserved" (outcomeOf descendants == Exited 0)
    assertNotRunning pid
    assert' "pipe inheritance bounded" (case descendants of ProcessReport {evidence = StageEvidence {durationSeconds}} -> durationSeconds < 2)
    observerFailed <- runCommand (case opts "observer" of ProcessOptions d p g ws e _ -> ProcessOptions d p g ws e (\_ _ -> ioError (userError "observer failed"))) workspace Test (command ["sleep"] 5000000)
    assert' "observer failure captured" (case observerFailed of ProcessReport {errors} -> not (null errors))
    forM_ [1 .. 3 :: Int] $ \n -> do
      done <- newEmptyMVar
      let cancelMarker = root </> ("cancel-" ++ show n ++ ".pid")
      tid <- forkFinally (run ("cancel-" ++ show n) ["ignore", cancelMarker] 5000000) (putMVar done)
      waitMarker cancelMarker
      cancelPid <- read <$> readFile cancelMarker
      throwTo tid ThreadKilled
      _ <- forkIO (throwTo tid ThreadKilled)
      completed <- timeout 2000000 (takeMVar done)
      let cancelledWithEvidence = case completed of
            Just (Left e) -> case fromException e of
              Just ProcessAborted {} -> True
              Nothing -> False
            _ -> False
      assert' "asynchronous cancellation carries evidence" cancelledWithEvidence
      assertNotRunning cancelPid
    -- Detached processes are outside group supervision. The test owns and
    -- explicitly cleans up this PID; this documents the boundary.
    let detachedMarker = root </> "detached.pid"
    detached <- run "detach" ["detach", detachedMarker] 1000000
    detachedPid <- read <$> readFile detachedMarker
    signalProcess sigKILL detachedPid
    assert' "detached pipe writer reported" (case detached of ProcessReport {errors} -> not (null errors))
  putStrLn "POSIX process outcome, timeout, descendant, cancellation and bounded log checks passed"

waitMarker :: FilePath -> IO ()
waitMarker p = do
  exists <- Dir.doesFileExist p
  if exists
    then do contents <- readFile p; if null contents then threadDelay 5000 >> waitMarker p else pure ()
    else threadDelay 5000 >> waitMarker p

assertNotRunning :: System.Posix.Types.ProcessID -> IO ()
assertNotRunning pid = do
  -- signal 0 may still observe an orphan zombie until the system reaps it.
  -- A second fixture-independent query uses the OS process state via getProcessStatus
  -- only for owned direct children; marker descendants are checked through a
  -- bounded disappearance poll here.
  gone <- timeout 1000000 waitGone
  assert' "owned descendant no longer running" (gone == Just ())
  where
    waitGone = do
      alive <- try (signalProcess nullSignal pid) :: IO (Either IOException ())
      case alive of Left _ -> pure (); Right () -> threadDelay 5000 >> waitGone
