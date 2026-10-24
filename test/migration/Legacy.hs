-- | Independently authored finite comparison harnesses, not production runners
-- and not copies of the surveyed repositories. Deliberately exit-only verdicts
-- demonstrate why attributable evidence matters. Never used for hang fixtures.
module Legacy (runLegacy, copyFixture) where

import Control.Exception (bracket)
import Control.Monad (forM_, unless)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text
import System.Directory qualified as Dir
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.Posix.Temp (mkdtemp)
import System.Process qualified as P

-- BEGIN shared-orchestration
copyFixture :: FilePath -> FilePath -> IO ()
copyFixture source destination = do
  Dir.createDirectoryIfMissing True destination
  names <- Dir.listDirectory source
  forM_ names $ \name -> do
    directory <- Dir.doesDirectoryExist (source </> name)
    if directory
      then copyFixture (source </> name) (destination </> name)
      else Dir.copyFile (source </> name) (destination </> name)

withCopy :: FilePath -> (FilePath -> IO a) -> IO a
withCopy source action = bracket (Dir.getTemporaryDirectory >>= \p -> mkdtemp (p </> "legacy-comparison-")) Dir.removePathForcibly $ \root -> copyFixture source root >> action root

command :: FilePath -> String -> [String] -> IO ExitCode
command root exe args = do
  (code, _, _) <- P.readCreateProcessWithExitCode ((P.proc exe args) {P.cwd = Just root}) ""
  pure code

baseline :: ExitCode -> IO ()
baseline code = unless (code == ExitSuccess) (error "comparison fixture baseline failed")

-- END shared-orchestration

runLegacy :: String -> FilePath -> IO Bool
runLegacy "replacement" source = withCopy source $ \root -> do
  -- BEGIN replacement-orchestration
  command root "cabal" ["test", "fixture-test", "--offline", "-j1"] >>= baseline
  -- BEGIN replacement-definition
  text <- Text.readFile (root </> "src/Capacity.hs")
  Text.writeFile (root </> "src/Capacity.hs") (Text.replace "used < limit" "True" text)
  -- END replacement-definition
  code <- command root "cabal" ["test", "fixture-test", "--offline", "-j1"]
  pure (code /= ExitSuccess)
-- END replacement-orchestration
runLegacy "patch-catalogue" source = withCopy source $ \root -> do
  -- BEGIN patch-catalogue-orchestration
  command root "cabal" ["test", "fixture-test", "--offline", "-j1"] >>= baseline
  -- BEGIN patch-catalogue-definition
  command root "git" ["apply", "--check", "patches/guard-bypass.patch"] >>= baseline
  command root "git" ["apply", "patches/guard-bypass.patch"] >>= baseline
  -- END patch-catalogue-definition
  code <- command root "cabal" ["test", "fixture-test", "--offline", "-j1"]
  pure (code /= ExitSuccess)
-- END patch-catalogue-orchestration
runLegacy "generated-code" source = withCopy source $ \root -> do
  -- BEGIN generated-code-orchestration
  command root "runghc" ["tools/Build.hs"] >>= baseline
  command root "cabal" ["test", "fixture-test", "--offline", "-j1"] >>= baseline
  -- BEGIN generated-code-definition
  text <- Text.readFile (root </> "model.txt")
  Text.writeFile (root </> "model.txt") (Text.replace "mode=strict" "mode=open" text)
  -- END generated-code-definition
  built <- command root "runghc" ["tools/Build.hs"]
  if built /= ExitSuccess then pure True else (/= ExitSuccess) <$> command root "cabal" ["test", "fixture-test", "--offline", "-j1"]
-- END generated-code-orchestration
runLegacy "diagnostic-checker" source = withCopy source $ \root -> do
  -- BEGIN diagnostic-checker-orchestration
  command root "runghc" ["tools/Build.hs"] >>= baseline
  command root "./dist-newstyle/checker" [] >>= baseline
  -- BEGIN diagnostic-checker-definition
  text <- Text.readFile (root </> "policy.txt")
  Text.writeFile (root </> "policy.txt") (Text.replace "capacity=10" "capacity=-1" text)
  -- END diagnostic-checker-definition
  (/= ExitSuccess) <$> command root "./dist-newstyle/checker" []
-- END diagnostic-checker-orchestration
-- A finite negative comparison: this is the historical exit-only mistake.
runLegacy "unrelated-compile-failure" source = withCopy source $ \root -> do
  command root "cabal" ["test", "fixture-test", "--offline", "-j1"] >>= baseline
  text <- Text.readFile (root </> "src/Capacity.hs")
  Text.writeFile (root </> "src/Capacity.hs") (Text.replace "used < limit" "missingCapacityGuard" text)
  (/= ExitSuccess) <$> command root "cabal" ["test", "fixture-test", "--offline", "-j1"]
runLegacy _ _ = error "unknown comparison family"
