{-# LANGUAGE CPP #-}

-- | Hspec formatter and an explicit QuickCheck replay helper. Replace @hspec@
-- with 'heniHspec'; framework dependencies stay outside Heni's core.
module Test.Heni.Hspec (heniHspec, heniProperty) where

import Control.Exception (throwIO)
import Control.Monad (unless, when)
import Data.Maybe (fromMaybe)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import System.Environment (getArgs, lookupEnv)
import System.IO (hPutStrLn, stderr)
import Test.Heni.Adapter
import Test.Heni.Expectation (ReplayEvidence (..))
import Test.Hspec qualified as H
import Test.Hspec.Api.Format.V2 qualified as F
import Test.Hspec.Core.Runner qualified as R
import Test.QuickCheck qualified as QC
import Test.QuickCheck.Random (QCGen)
import Text.Read (readMaybe)

-- | Native Hspec options are parsed first; the Heni selector is a stable-ID
-- substring intersected with that selection. History-based reruns are rejected
-- inside an attempt because they can execute a different test set.
heniHspec :: H.Spec -> IO ()
heniHspec spec =
  currentEvidenceAttempt >>= \case
    Nothing -> H.hspec spec
    Just attempt -> guardEvidenceAttempt attempt $ do
      (initial, forest) <- R.evalSpec R.defaultConfig spec
      args <- getArgs
      config <- R.readConfig initial args
      when (R.configRerun config || R.configRerunAllOnSuccess config) (throwIO (EvidenceError "Hspec history reruns are unsupported inside a Heni attempt"))
      when (R.configDryRun config) (throwIO (EvidenceError "Hspec dry-run does not prove execution inside a Heni attempt"))
      selector <- fmap Text.pack <$> lookupEnv "HENI_SELECTOR"
      let include path = fromMaybe (const True) (R.configFilterPredicate config) path && maybe True (`Text.isInfixOf` pathId path) selector
          finalConfig = F.useFormatter ("heni", formatter attempt) config {R.configFilterPredicate = Just include}
      R.runSpecForest forest finalConfig >>= R.evaluateResult

pathId :: F.Path -> Text
pathId (groups, name) = stableTestId (map Text.pack (groups ++ [name]))

formatter :: EvidenceAttempt -> F.FormatConfig -> IO F.Format
formatter attempt config = pure $ \case
  F.Done items -> do
    property <- readPropertyReplay attempt
    let ids = map (pathId . fst) items
        errors = ["Hspec completed a partial selection" | length items /= F.formatConfigExpectedTotalCount config]
        observation (path, item) = case F.itemResult item of
          F.Success -> TestPassed (pathId path)
          F.Pending {} -> TestSkipped (pathId path)
          F.Failure _ (F.Error _ e) -> TestSetupFailed (pathId path) (Text.pack (show e))
          F.Failure {} -> TestFailed (pathId path)
    emitSuite attempt (SuiteEvidence ("hspec/" <> Text.pack VERSION_hspec <> ";heni-hspec/0.1.0.0") Nothing ids (map observation items) errors (fst <$> property) (maybe [] snd property))
  _ -> pure ()

-- | The ID must equal the enclosing Hspec example's stable full ID. Records
-- QuickCheck's native seed/size, generator arguments and failing input. Exactly
-- one replay property is supported per selected attempt. Invalid replay data
-- makes the example pending, which can never satisfy a required reproduction.
heniProperty :: (QC.Testable property) => Text -> QC.Args -> property -> H.Expectation
heniProperty ident args property = do
  token <- lookupEnv "HENI_REPLAY_TOKEN"
  expectedGenerator <- lookupEnv "HENI_REPLAY_GENERATOR"
  let generator = Text.pack ("QuickCheck/" ++ VERSION_QuickCheck ++ ";" ++ show (QC.maxSuccess args, QC.maxDiscardRatio args, QC.maxSize args, QC.maxShrinks args))
      reject why = hPutStrLn stderr why >> H.pendingWith why
  replay <- case token of
    Nothing -> pure (QC.replay args)
    Just value -> do
      unless (expectedGenerator == Just (Text.unpack generator)) (reject "QuickCheck generator configuration mismatch")
      case readMaybe value :: Maybe (QCGen, Int) of
        Nothing -> reject "invalid native QuickCheck replay token" >> pure Nothing
        Just pair -> pure (Just pair)
  result <- QC.quickCheckWithResult (args {QC.chatty = False, QC.replay = replay, QC.maxSuccess = if token == Nothing then QC.maxSuccess args else 1}) property
  case result of
    QC.Success {} -> pure ()
    QC.Failure {QC.usedSeed, QC.usedSize, QC.theException, QC.failingTestCase, QC.output} -> do
      case theException of Just e -> throwIO e; Nothing -> pure ()
      recordPropertyReplay (ReplayEvidence (Text.pack (show (usedSeed, usedSize))) generator (Set.singleton ident)) (map Text.pack failingTestCase)
      H.expectationFailure output
    other -> H.pendingWith (QC.output other)
