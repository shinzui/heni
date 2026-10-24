-- | Bounded commands, owned POSIX groups and independent stdout/stderr evidence.
module Test.Heni.Process
  ( Stream (..),
    LogArtifact (..),
    ProcessOptions (..),
    defaultProcessOptions,
    ProcessReport (..),
    ProcessAborted (..),
    runCommand,
    validateExecutable,
  )
where

import Control.Concurrent
import Control.Exception hiding (handle)
import Control.Monad (unless)
import Data.ByteString qualified as BS
import Data.IORef
import Data.List (nub)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import GHC.Clock (getMonotonicTimeNSec)
import System.Directory qualified as Dir
import System.Environment (getEnvironment)
import System.FilePath (isPathSeparator, (</>))
import System.IO
import System.Process qualified as P
import System.Timeout (timeout)
import Test.Heni.Case (ConfigError (..))
import Test.Heni.Command
import Test.Heni.Expectation
import Test.Heni.Internal.Process.Posix
import Test.Heni.Workspace

-- | Streams remain separate; a witness cannot span stdout and stderr.
data Stream = Stdout | Stderr deriving stock (Eq, Show)

-- | Bounded retained bytes and total byte count; paths are portable basenames.
data LogArtifact = LogArtifact
  {stream :: !Stream, path :: !FilePath, bytesSeen :: !Integer, bytesRetained :: !Int, truncated :: !Bool}
  deriving stock (Eq, Show)

-- | Observation callbacks may fail but cannot alter process outcomes.
data ProcessOptions = ProcessOptions
  { logDirectory :: !FilePath,
    logPrefix :: !String,
    graceBudget :: !StageBudget,
    witnesses :: ![Text],
    environmentRemovals :: ![String],
    observer :: !(Stream -> BS.ByteString -> IO ())
  }

-- | A 200ms grace period and no diagnostic matching; specify an owned log directory.
defaultProcessOptions :: FilePath -> String -> ProcessOptions
defaultProcessOptions directory prefix = ProcessOptions directory prefix grace [] [] (\_ _ -> pure ())
  where
    grace = either (error . show) id (mkStageBudget 200000)

-- | Primary stage facts plus bounded log metadata and secondary shutdown errors.
data ProcessReport = ProcessReport
  {evidence :: !StageEvidence, logs :: ![LogArtifact], preservedWitnesses :: ![Text], errors :: ![Text]}
  deriving stock (Eq, Show)

-- | Cancellation retains final process evidence. Campaigns finalize their ledger,
-- then rethrow cause to honor the original asynchronous exception.
data ProcessAborted = ProcessAborted {report :: !ProcessReport, cause :: !SomeException}
  deriving stock (Show)
  deriving anyclass (Exception)

-- | Resolve availability before execution. Launch races are still handled in IO.
validateExecutable :: Command -> IO (Either ConfigError ())
validateExecutable command@Command {executable} = case validateCommand command of
  Left e -> pure (Left e)
  Right () -> do
    found <- Dir.findExecutable executable
    pure $ maybe (Left (ConfigError "executable" "executable is unavailable")) (const (Right ())) found

data Capture = Capture !Integer !BS.ByteString !BS.ByteString ![Text]

-- | Run literal executable/argv in an exclusive workspace. Logs are bounded per
-- stream. Exact requested witnesses are scanned through all bytes and retained
-- separately, so log truncation alone cannot erase a proved witness.
runCommand :: ProcessOptions -> Workspace -> Stage -> Command -> IO ProcessReport
runCommand ProcessOptions {logDirectory, logPrefix, graceBudget, witnesses, environmentRemovals, observer} workspace stage command@Command {executable, arguments, workingDirectory, environment, budget, output = OutputPolicy {limitBytes}} = do
  started <- getMonotonicTimeNSec
  let failed why = pure (ProcessReport (StageEvidence stage (LaunchFailed why) "" False unknownSelection Nothing 0 []) [] [] [why])
  case validateCommand command of
    Left e -> failed (Text.pack (show e))
    Right () | null logPrefix || any isPathSeparator logPrefix || logPrefix `elem` [".", ".."] -> failed "invalid log prefix"
    Right () | sum (map (BS.length . Text.encodeUtf8) witnesses) > 65536 || any Text.null witnesses -> failed "diagnostic witnesses must be nonempty and total at most 64KiB"
    Right () -> do
      launch <- try $ do
        cwd <- maybe (pure (workspaceRoot workspace)) (checkedWorkspacePath workspace) workingDirectory
        isDirectory <- Dir.doesDirectoryExist cwd
        unless isDirectory (ioError (userError "working directory does not exist"))
        inherited <- getEnvironment
        let overrides = Map.fromList environment
            effective = Map.toList (overrides `Map.union` foldr Map.delete (Map.fromList inherited) environmentRemovals)
        Dir.createDirectoryIfMissing True logDirectory
        withBinaryFile (logDirectory </> logPrefix ++ ".stdout.log") WriteMode $ \outLog ->
          withBinaryFile (logDirectory </> logPrefix ++ ".stderr.log") WriteMode $ \errLog ->
            supervise started cwd effective outLog errLog
      case launch of
        Left (e :: IOException) -> failed (Text.pack (show e))
        Right result -> pure result
  where
    supervise started cwd effective outLog errLog = mask $ \restore -> do
      -- Dependency-owned record update is isolated to the process adapter; no
      -- label instances propagate through the public library.
      let spec =
            (P.proc executable arguments)
              { P.cwd = Just cwd,
                P.env = Just effective,
                P.std_in = P.NoStream,
                P.std_out = P.CreatePipe,
                P.std_err = P.CreatePipe,
                P.create_group = True,
                P.close_fds = True
              }
      (_, maybeOut, maybeErr, process) <- P.createProcess spec
      pid <- P.getPid process
      case (maybeOut, maybeErr) of
        (Just stdoutHandle, Just stderrHandle) -> do
          outRef <- newIORef (Capture 0 BS.empty BS.empty [])
          errRef <- newIORef (Capture 0 BS.empty BS.empty [])
          outDone <- newEmptyMVar
          errDone <- newEmptyMVar
          outThread <- forkFinally (restore (drain Stdout stdoutHandle outLog outRef)) (putMVar outDone)
          errThread <- forkFinally (restore (drain Stderr stderrHandle errLog errRef)) (putMVar errDone)
          let poll = do
                readerFailure <- firstFailure [outDone, errDone]
                case readerFailure of
                  Just e -> throwIO e
                  Nothing -> do
                    exit <- P.getProcessExitCode process
                    now <- getMonotonicTimeNSec
                    case exit of
                      Just code -> pure (exitOutcome code)
                      Nothing | now - started >= fromIntegral (budgetMicroseconds budget) * 1000 -> pure Timeout
                      Nothing -> threadDelay 5000 >> poll
          primary <- try (restore poll) :: IO (Either SomeException ProcessOutcome)
          deferred <- newIORef Nothing
          let defer :: forall b. IO b -> IO b
              defer action =
                action `catch` \(e :: SomeAsyncException) -> do
                  writeIORef deferred (Just (toException e))
                  defer action
          -- Cleanup runs masked and has no blocking operation without a bound.
          shutdown <- uninterruptibleMask_ (stopGroup (budgetMicroseconds graceBudget) pid process)
          let finish tid handle done = do
                joined <- timeout (budgetMicroseconds graceBudget) (readMVar done)
                case joined of
                  Nothing -> do
                    _ <- timeout (budgetMicroseconds graceBudget) (killThread tid)
                    _ <- timeout (budgetMicroseconds graceBudget) (readMVar done)
                    closeQuietly handle
                    pure ["output reader did not finish within shutdown budget"]
                  Just (Left e) -> closeQuietly handle >> pure [Text.pack (displayException e)]
                  Just (Right ()) -> closeQuietly handle >> pure []
          outErrors <- defer (finish outThread stdoutHandle outDone)
          errErrors <- defer (finish errThread stderrHandle errDone)
          flushResult <- defer (try (hFlush outLog >> hFlush errLog)) :: IO (Either IOException ())
          secondaryCancellation <- readIORef deferred
          outCapture <- readIORef outRef
          errCapture <- readIORef errRef
          ended <- getMonotonicTimeNSec
          let found = nub (captureWitnesses outCapture ++ captureWitnesses errCapture)
              -- Only exact byte-matched witnesses enter classifier text. Lenient
              -- display decoding of malformed UTF-8 must never invent a match.
              outputText = Text.intercalate "\n" found
              secondary = shutdown ++ outErrors ++ errErrors ++ either (\e -> [Text.pack (show e)]) (const []) flushResult
              primaryErrors = either (\e -> [Text.pack (displayException e)]) (const []) primary
              outcome = either (const Cancelled) id primary
              unavailable = not (null (primaryErrors ++ secondary)) || any (`notElem` found) witnesses && any captureTruncated [outCapture, errCapture]
              stageEvidence = StageEvidence stage outcome outputText unavailable unknownSelection Nothing (fromIntegral (ended - started) / 1e9) [logPrefix ++ ".stdout.log", logPrefix ++ ".stderr.log"]
              result = ProcessReport stageEvidence [artifact Stdout outCapture, artifact Stderr errCapture] found (primaryErrors ++ secondary)
          case primary of
            Left e | Just (_ :: SomeAsyncException) <- fromException e -> throwIO (ProcessAborted result e)
            _ -> case secondaryCancellation of
              Just e -> throwIO (ProcessAborted result e)
              Nothing -> pure result
        _ -> do
          _ <- stopGroup (budgetMicroseconds graceBudget) pid process
          ioError (userError "process library did not supply requested output pipes")
    captureWitnesses (Capture _ _ _ found) = found
    captureTruncated (Capture count b _ _) = count > fromIntegral (BS.length b)
    artifact stream capture@(Capture count b _ _) = LogArtifact stream (logPrefix ++ suffix stream) count (BS.length b) (captureTruncated capture)
    suffix Stdout = ".stdout.log"
    suffix Stderr = ".stderr.log"
    drain stream input logHandle ref = do
      chunk <- BS.hGetSome input 32768
      unless (BS.null chunk) $ do
        Capture count kept tailBytes found <- readIORef ref
        let retain = BS.take (max 0 (limitBytes - BS.length kept)) chunk
            haystack = tailBytes <> chunk
            newFound = nub (found ++ [w | w <- witnesses, Text.encodeUtf8 w `BS.isInfixOf` haystack])
            overlap = maximum (0 : map ((subtract 1) . BS.length . Text.encodeUtf8) witnesses)
            nextTail = BS.drop (max 0 (BS.length haystack - overlap)) haystack
        BS.hPut logHandle retain
        writeIORef ref (Capture (count + fromIntegral (BS.length chunk)) (kept <> retain) nextTail newFound)
        observer stream chunk
        drain stream input logHandle ref

firstFailure :: [MVar (Either SomeException ())] -> IO (Maybe SomeException)
firstFailure [] = pure Nothing
firstFailure (done : rest) = do
  result <- tryReadMVar done
  case result of Just (Left e) -> pure (Just e); _ -> firstFailure rest

closeQuietly :: Handle -> IO ()
closeQuietly handle = do
  _ <- try (hClose handle) :: IO (Either IOException ())
  pure ()
