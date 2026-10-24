-- | Narrow POSIX group termination. Detached descendants require a sandbox.
module Test.Heni.Internal.Process.Posix (stopGroup, exitOutcome) where

import Control.Concurrent (threadDelay)
import Control.Exception
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

-- | Signal only while the owned group remains observable. Once absence has
-- been observed, never send another signal to that transient numeric identity.
-- Reap the direct child independently; all waits have explicit bounds.
stopGroup :: Int -> Maybe Pid -> ProcessHandle -> IO [Text]
stopGroup grace pid process = do
  initial <- groupState
  termErrors <- case initial of Right False -> pure []; _ -> send sigTERM
  deadline <- (+ fromIntegral grace * 1000) <$> getMonotonicTimeNSec
  remaining <- case initial of
    Right False -> pure (Right False)
    _ -> waitGroup deadline
  killErrors <- case remaining of Right False -> pure []; _ -> send sigKILL
  reapDeadline <- (+ fromIntegral grace * 1000) <$> getMonotonicTimeNSec
  final <- case remaining of Right False -> pure (Right False); _ -> waitGroup reapDeadline
  reaped <- reap reapDeadline
  -- Darwin can temporarily return EPERM for a group whose members are exiting.
  -- Only proven disappearance clears these provisional observation/send errors.
  let shutdownErrors = case final of
        Right False -> []
        _ -> either pure (const []) initial ++ termErrors ++ either pure (const []) final ++ killErrors
  pure (shutdownErrors ++ ["direct child could not be reaped within shutdown budget" | not reaped])
  where
    send signal = case pid of
      Nothing -> pure ["missing owned process group identity"]
      Just group -> do
        result <- try (signalProcessGroup signal group)
        case result of
          Right () -> pure []
          Left e | isDoesNotExistError e -> pure []
          Left (e :: IOException) -> do
            -- A disappearing group can make a redundant signal fail. Accept
            -- only definite absence, never a permission/observation failure.
            after <- groupState
            pure $ case after of
              Right False -> []
              _ -> ["sending signal " <> Text.pack (show signal) <> " to owned group: " <> Text.pack (displayException e)]
    groupState = case pid of
      Nothing -> pure (Left "missing owned process group identity")
      Just group -> do
        result <- try (signalProcessGroup nullSignal group) :: IO (Either IOException ())
        pure $ case result of
          Right () -> Right True
          Left e | isDoesNotExistError e -> Right False
          Left e -> Left ("probing owned process group: " <> Text.pack (displayException e))
    waitGroup deadline = do
      _ <- getProcessExitCode process
      state <- groupState
      now <- getMonotonicTimeNSec
      case state of
        Right False -> pure state
        _ | now >= deadline -> pure state
        _ -> threadDelay 5000 >> waitGroup deadline
    reap deadline = do
      result <- getProcessExitCode process
      now <- getMonotonicTimeNSec
      case result of
        Just _ -> pure True
        Nothing | now >= deadline -> pure False
        Nothing -> threadDelay 5000 >> reap deadline
