-- | Narrow POSIX group termination. Detached descendants require a sandbox.
module Test.Heni.Internal.Process.Posix (stopGroup, exitOutcome) where

import Control.Concurrent (threadDelay)
import Control.Exception
import Control.Monad (unless)
import Data.Text (Text)
import Data.Text qualified as Text
import GHC.Clock (getMonotonicTimeNSec)
import System.Exit (ExitCode (..))
import System.IO.Error (isDoesNotExistError)
import System.Posix.Signals
import System.Process (Pid, ProcessHandle, getProcessExitCode)
import Test.Heni.Command (ProcessOutcome (..))

exitOutcome :: ExitCode -> ProcessOutcome
exitOutcome ExitSuccess = Exited 0
exitOutcome (ExitFailure n) | n < 0 = Signaled (negate n)
exitOutcome (ExitFailure n) = Exited n

-- | Always terminate remaining group members, even after the leader exited.
-- All polling is bounded; no unbounded waitForProcess is used in cleanup.
stopGroup :: Int -> Maybe Pid -> ProcessHandle -> IO [Text]
stopGroup grace pid process = do
  termErrors <- send sigTERM
  deadline <- (+ fromIntegral grace * 1000) <$> getMonotonicTimeNSec
  waitGroup deadline
  killErrors <- send sigKILL
  reapDeadline <- (+ fromIntegral grace * 1000) <$> getMonotonicTimeNSec
  reaped <- reap reapDeadline
  pure (termErrors ++ killErrors ++ ["direct child could not be reaped within shutdown budget" | not reaped])
  where
    send signal = case pid of
      Nothing -> pure ["missing owned process group identity"]
      Just group -> do
        result <- try (signalProcessGroup signal group)
        pure $ case result of
          Left e | isDoesNotExistError e -> []
          Left (e :: IOException) -> [Text.pack (show e)]
          Right () -> []
    groupAlive = case pid of
      Nothing -> pure False
      Just group -> do
        result <- try (signalProcessGroup nullSignal group) :: IO (Either IOException ())
        pure $ case result of Right () -> True; Left _ -> False
    waitGroup deadline = do
      -- Reap a finished leader while checking the remaining owned group.
      _ <- getProcessExitCode process
      alive <- groupAlive
      now <- getMonotonicTimeNSec
      unless (not alive || now >= deadline) (threadDelay 5000 >> waitGroup deadline)
    reap deadline = do
      result <- getProcessExitCode process
      now <- getMonotonicTimeNSec
      case result of
        Just _ -> pure True
        Nothing | now >= deadline -> pure False
        Nothing -> threadDelay 5000 >> reap deadline
