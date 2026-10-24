-- | Bounded workers with atomic multi-resource claims and owned cancellation.
module Test.Heni.Scheduler (runScheduled) where

import Control.Concurrent
import Control.Concurrent.STM
import Control.Exception
import Control.Monad (forM, forM_, replicateM_, unless)
import Data.List (findIndex)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Test.Heni.Internal.Files (WorkspaceFinalizationError (..), withFinalizer)

-- | Run a finite author-ordered queue. Claims are acquired atomically; a blocked
-- item can be passed by independent work, and becomes eligible when its owners
-- release capacity. Failures cancel/join every worker before returning. This
-- coordinates one process only; external processes require external locks.
runScheduled :: Int -> Map.Map Text Int -> [(a, [Text])] -> (Int -> IO () -> IO ()) -> (Int -> a -> IO ()) -> IO ()
runScheduled count capacities work withWorker action = do
  unless (count > 0 && count <= 256 && all (> 0) (Map.elems capacities)) (ioError (userError "invalid worker count or resource capacity"))
  forM_ work $ \(_, claims) -> unless (all (`Map.member` capacities) claims && Set.size (Set.fromList claims) == length claims) (ioError (userError "unknown or duplicate resource claim"))
  mask $ \restore -> do
    queue <- newTVarIO work
    active <- newTVarIO Map.empty
    completed <- newChan
    let takeWork = do
          remaining <- readTVar queue
          case remaining of
            [] -> pure Nothing
            _ -> do
              usage <- readTVar active
              let available (_, claims) = all (\name -> Map.findWithDefault 0 name usage < capacities Map.! name) claims
              case findIndex available remaining of
                Nothing -> retry
                Just index -> case splitAt index remaining of
                  (before, (item, claims) : after) -> do
                    writeTVar queue (before ++ after)
                    writeTVar active (foldr (\name -> Map.insertWith (+) name 1) usage claims)
                    pure (Just (item, claims))
                  _ -> retry
        release claims = atomically (modifyTVar' active (\usage -> foldr (Map.adjust (subtract 1)) usage claims))
        worker number = mask $ \restoreWorker ->
          atomically takeWork >>= \case
            Nothing -> pure ()
            Just (item, claims) -> (restoreWorker (action number item) `withFinalizer` release claims) >> restoreWorker (worker number)
    handles <- forM [1 .. min count (max 1 (length work))] $ \number -> do
      done <- newEmptyMVar
      tid <- forkIOWithUnmask $ \unmask -> do
        result <- try (unmask (withWorker number (worker number)))
        putMVar done (result :: Either SomeException ())
        writeChan completed result
      pure (tid, done)
    let join = mapM_ (readMVar . snd) handles
        cancel = do
          forM_ handles (\(tid, _) -> throwTo tid ThreadKilled)
          states <- mapM (readMVar . snd) handles
          pure [e | Left e <- states, Nothing <- [fromException e :: Maybe SomeAsyncException]]
        await = replicateM_ (length handles) $ readChan completed >>= either throwIO pure
    outcome <- try (restore await)
    case outcome of
      Left (e :: SomeException) -> do
        secondary <- cancel
        throwIO (foldl (\primary extra -> toException (WorkspaceFinalizationError (Just primary) extra)) e secondary)
      Right () -> join
