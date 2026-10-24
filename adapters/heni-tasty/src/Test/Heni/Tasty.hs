{-# LANGUAGE CPP #-}

-- | Replace @defaultMain@ with 'heniMain'. Outside a Heni attempt, Tasty's
-- ordinary console, filters and options remain available.
module Test.Heni.Tasty (heniMain) where

import Control.Concurrent.STM
import Control.Monad (unless)
import Data.IntMap.Strict qualified as IntMap
import Data.Text qualified as Text
import System.Environment (getArgs, lookupEnv, withArgs)
import Test.Heni.Adapter
import Test.Tasty qualified as Tasty
import Test.Tasty.Ingredients.Basic (consoleTestReporter)
import Test.Tasty.Runners qualified as R

-- | Under Heni, a dedicated reporter owns completion after resource finalizers.
-- HENI_SELECTOR is a native Tasty pattern, intersected with existing patterns.
heniMain :: Tasty.TestTree -> IO ()
heniMain tree =
  currentEvidenceAttempt >>= \case
    Nothing -> Tasty.defaultMain tree
    Just attempt -> guardEvidenceAttempt attempt $ do
      args <- getArgs
      selector <- lookupEnv "HENI_SELECTOR"
      let extra = maybe [] (\s -> ["--pattern", s]) selector
      withArgs (args ++ extra) (R.defaultMainWithIngredients [reporter attempt] tree)

reporter :: EvidenceAttempt -> R.Ingredient
reporter attempt = R.TestReporter consoleOptions $ \opts tree -> Just $ \statuses -> do
  let ids = map stableTestId (R.foldTestTree paths opts tree)
  results <- atomically (mapM waitDone (IntMap.elems statuses))
  unless (length ids == length results) (ioError (userError "Tasty status/selection identity mismatch"))
  pure $ \_ -> do
    property <- readPropertyReplay attempt
    let observations = zipWith observation ids results
    emitSuite attempt (SuiteEvidence ("tasty/" <> Text.pack VERSION_tasty <> ";heni-tasty/0.1.0.0") Nothing ids observations [] (fst <$> property) (maybe [] snd property))
    pure (all R.resultSuccessful results)
  where
    consoleOptions = case consoleTestReporter of R.TestReporter options _ -> options; _ -> []
    waitDone status = readTVar status >>= \case R.Done result -> pure result; _ -> retry
    paths =
      R.trivialFold
        { R.foldSingle = \_ name _ -> [[Text.pack name]],
          R.foldGroup = \_ name groups -> map (Text.pack name :) (concat groups)
        }
    observation ident result = case R.resultOutcome result of
      R.Success -> TestPassed ident
      R.Failure R.TestFailed -> TestFailed ident
      R.Failure R.TestDepFailed -> TestSkipped ident
      R.Failure reason -> TestSetupFailed ident (Text.pack (show reason))
