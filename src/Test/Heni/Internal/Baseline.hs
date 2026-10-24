-- | Campaign-local single-flight baseline sharing. Keys may contain secrets and
-- are never serialized or hashed for portable reports.
module Test.Heni.Internal.Baseline (BaselineCache, newBaselineCache, clearBaselineCache, shareBaseline) where

import Control.Concurrent.MVar
import Control.Exception

newtype BaselineCache key value = BaselineCache (MVar [(key, MVar (Maybe value))])

newBaselineCache :: IO (BaselineCache key value)
newBaselineCache = BaselineCache <$> newMVar []

clearBaselineCache :: BaselineCache key value -> IO ()
clearBaselineCache (BaselineCache cache) = modifyMVar_ cache (const (pure []))

-- | The producer returns Nothing for an unshareable observation. Waiters then
-- execute independently. Cancellation publishes Nothing before rethrowing so
-- another worker can never remain blocked on abandoned ownership.
shareBaseline :: (Eq key) => BaselineCache key value -> key -> IO (Maybe value) -> IO (Bool, Maybe value)
shareBaseline (BaselineCache cache) key compute = mask $ \restore -> do
  (owner, slot) <- modifyMVar cache $ \entries -> case lookup key entries of
    Just existing -> pure (entries, (False, existing))
    Nothing -> do fresh <- newEmptyMVar; pure ((key, fresh) : entries, (True, fresh))
  if owner
    then do
      result <- try (restore compute)
      case result of
        Left (e :: SomeException) -> putMVar slot Nothing >> throwIO e
        Right value -> putMVar slot value >> pure (False, value)
    else do
      cached <- restore (readMVar slot)
      case cached of
        Just value -> pure (True, Just value)
        Nothing -> (False,) <$> restore compute
