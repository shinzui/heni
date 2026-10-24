-- | Explicit build-tool contracts for retaining private worker artifacts.
-- Generic commands have no automatic invalidation guarantee and default fresh.
module Test.Heni.BuildReuse
  ( BuildReuse (..),
    BuildWorker,
    BuildReuseError (..),
    validateBuildReuse,
    withBuildWorker,
    withBuildCandidate,
    confirmBuild,
    retireBuildWorker,
  )
where

import Control.Exception
import Control.Monad (forM_, unless, when)
import Data.IORef
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory qualified as Dir
import System.FilePath (splitDirectories, (</>))
import Test.Heni.Case
import Test.Heni.Internal.Files
import Test.Heni.Workspace

-- | A consumer promises a content-key-aware build tool. Before tests, the
-- verifier must prove that the completed build observed HENI_BUILD_INPUT_ID.
-- The preparation callback can enforce conservative timestamp behavior. Neither
-- callback is an attestation against malicious commands. This hook is Haskell
-- only because arbitrary build tools cannot share one reliable portable check.
data BuildReuse = BuildReuse
  { contractIdentity :: !Text,
    retainedDirectories :: ![RelativeTarget],
    prepareInputs :: !(Workspace -> IO ()),
    verifyBuildObservation :: !(Workspace -> Text -> IO (Either Text ()))
  }

-- | Invalidation/reset failures invalidate the current case, never a kill.
newtype BuildReuseError = BuildReuseError Text
  deriving stock (Eq, Show)
  deriving anyclass (Exception)

-- | One private workspace and an in-memory command/environment contract.
data BuildWorker key = BuildWorker !SourceSnapshot !BuildReuse !Workspace !(IORef (Maybe (key, Inventory))) !(IORef Bool)

-- | Retain only known top-level build directories, never selected source paths.
validateBuildReuse :: BuildReuse -> Either ConfigError ()
validateBuildReuse BuildReuse {contractIdentity, retainedDirectories} = do
  unless (not (Text.null (Text.strip contractIdentity)) && not (null retainedDirectories)) (Left (ConfigError "buildReuse" "nonempty contract and build directories required"))
  unless (all (\p -> targetPath p `elem` ["dist", "dist-newstyle", ".heni-build"]) retainedDirectories) (Left (ConfigError "buildReuse.directories" "only dist, dist-newstyle or .heni-build can be retained"))

-- | The workspace is never shared with another worker and is discarded at exit.
withBuildWorker :: SourceSnapshot -> BuildReuse -> (BuildWorker key -> IO a) -> IO a
withBuildWorker snapshot provider action = withWorkspace snapshot $ \workspace -> do
  previous <- newIORef Nothing
  dirty <- newIORef True
  action (BuildWorker snapshot provider workspace previous dirty)

-- | Retire retained artifacts after any suspicious lifecycle result.
retireBuildWorker :: BuildWorker key -> IO ()
retireBuildWorker (BuildWorker _ _ _ _ dirty) = writeIORef dirty True

-- | Independently verify the previous source tree, restore exact staged bytes,
-- preserve private build directories, and verify source again after use. A
-- retired worker starts by deleting all retained artifacts from its owned tree.
withBuildCandidate :: (Eq key) => BuildWorker key -> key -> Workspace -> (Workspace -> Text -> IO a) -> IO a
withBuildCandidate worker@(BuildWorker snapshot BuildReuse {retainedDirectories, prepareInputs} workspace previous dirty) key staged action =
  operation `onException` retireBuildWorker worker
  where
    names = map targetPath retainedDirectories
    excluded path = case splitDirectories path of first : _ -> first `elem` names; [] -> False
    operation = do
      old <- readIORef previous
      retired <- readIORef dirty
      when (retired || maybe True ((/= key) . fst) old) (resetWorkspace snapshot workspace >> writeIORef previous Nothing)
      saved <- readIORef previous
      forM_ saved $ \(_, expected) ->
        inventory excluded (workspaceRoot workspace) >>= \actual ->
          unless (actual == expected) (throwIO (BuildReuseError "unexpected source/generated state in retained worker"))
      expected <- inventory (const False) (workspaceRoot staged)
      entries <- Dir.listDirectory (workspaceRoot workspace)
      forM_ (filter (`notElem` names) entries) (Dir.removePathForcibly . (workspaceRoot workspace </>))
      materialize (workspaceRoot workspace) expected
      actual <- inventory excluded (workspaceRoot workspace)
      unless (actual == expected) (throwIO (BuildReuseError "restored build inputs do not match staged mutation"))
      let inputId = inventoryDigest "heni-build-input-v1" expected
      prepareInputs workspace
      verified <- inventory excluded (workspaceRoot workspace)
      unless (verified == expected) (throwIO (BuildReuseError "build preparation changed selected input bytes"))
      value <- action workspace inputId
      final <- inventory excluded (workspaceRoot workspace)
      unless (final == expected) (throwIO (BuildReuseError "build/test changed source or created undeclared generated inputs"))
      writeIORef previous (Just (key, expected))
      writeIORef dirty False
      pure value

-- | Check the build-tool observation before running tests against its artifacts.
confirmBuild :: BuildWorker key -> Text -> IO ()
confirmBuild (BuildWorker _ BuildReuse {verifyBuildObservation} workspace _ _) inputId =
  verifyBuildObservation workspace inputId >>= either (throwIO . BuildReuseError) pure
