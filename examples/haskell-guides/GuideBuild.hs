module GuideBuild (buildFixture, testFixture, contentAddressedReuse, runReuse) where

import Control.Monad (forM_, unless, when)
import Data.ByteString qualified as BS
import Data.Text qualified as Text
import GuideSupport
import System.Directory qualified as Dir
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath ((</>))
import System.Process (rawSystem)
import Test.Heni qualified as H
import Test.Heni.BuildReuse qualified as Build
import Test.Heni.Workspace qualified as W

inputFiles :: [FilePath]
inputFiles = ["Subject.hs", "Checker.hs"]

-- The build wrapper is a cooperating child in Heni's owned process group.
-- It only compiles these two closed, base-only inputs with fixed flags.
buildFixture :: FilePath -> String -> IO ()
buildFixture ghc behavior = do
  key <- maybe "fresh" id <$> lookupEnv "HENI_BUILD_INPUT_ID"
  case H.mkRelativeTarget key of
    Left err -> ioError (userError (show err))
    Right _ -> pure ()
  let directory = ".heni-build" </> key
      checker = directory </> "checker"
      completed = directory </> "completed"
  Dir.createDirectoryIfMissing True directory
  sameInputs <- and <$> mapM (sameInput directory) inputFiles
  binaryExists <- Dir.doesFileExist checker
  receiptExists <- Dir.doesFileExist completed
  reusable <- if receiptExists then (== key) <$> readFile completed else pure False
  unless (sameInputs && binaryExists && reusable) $ do
    when receiptExists (Dir.removeFile completed)
    forM_ inputFiles $ \file -> BS.readFile file >>= BS.writeFile (directory </> file)
    -- Fresh source copies and forced compilation bind a cache entry to bytes,
    -- even when consecutive input files have identical sizes and mtimes.
    outcome <-
      rawSystem
        ghc
        [ "-v0",
          "-fforce-recomp",
          "-package-env",
          "-",
          "-i",
          "-i" ++ directory,
          "-outputdir",
          directory,
          directory </> "Checker.hs",
          "-o",
          checker
        ]
    unless (outcome == ExitSuccess) (exitWith outcome)
    writeFile completed key
  putStrLn (if sameInputs && binaryExists && reusable then "content cache: hit" else "content cache: compiled")
  writeFile ".heni-build/active-input" (if behavior == "stale" && key /= "fresh" then "stale-input" else key)

sameInput :: FilePath -> FilePath -> IO Bool
sameInput directory file = do
  exists <- Dir.doesFileExist (directory </> file)
  if exists then (==) <$> BS.readFile file <*> BS.readFile (directory </> file) else pure False

testFixture :: IO ()
testFixture = do
  key <- readFile ".heni-build/active-input"
  exitWith =<< rawSystem (".heni-build" </> key </> "checker") []

-- A receipt alone is insufficient: also bind the compiled cache entry to the
-- restored input copies and a completion marker written after GHC succeeded.
contentAddressedReuse :: Text.Text -> Build.BuildReuse
contentAddressedReuse toolchain = Build.BuildReuse
  toolchain
  [target ".heni-build"]
  (const (pure ()))
  $ \workspace expected -> do
    let root = W.workspaceRoot workspace
        key = Text.unpack expected
        directory = root </> ".heni-build" </> key
    observed <- readFile (root </> ".heni-build/active-input")
    completed <- readFile (directory </> "completed")
    binaryExists <- Dir.doesFileExist (directory </> "checker")
    same <-
      and
        <$> mapM
          (\file -> (==) <$> BS.readFile (root </> file) <*> BS.readFile (directory </> file))
          inputFiles
    pure $
      if observed == key && completed == key && binaryExists && same
        then Right ()
        else Left "build receipt or compiled input copies do not match the staged input"

runReuse :: FilePath -> FilePath -> Text.Text -> FilePath -> FilePath -> IO ()
runReuse self ghc toolchain source output = do
  let definitions =
        [ (definition "first" [guardEdit] diagnostic, H.noHooks),
          (definition "middle" [H.Replace (target "Subject.hs") "baseline" "harmless" 1] diagnostic, H.noHooks),
          (definition "last" [guardEdit] diagnostic, H.noHooks)
        ]
      selected behavior = campaign (commands self ghc behavior) definitions
      options name = H.defaultRunOptions source (output </> name)
  fresh <- H.runCampaign (options "fresh") (selected "normal")
  retained <- H.runCampaign ((options "retained") {H.buildReuse = Just (contentAddressedReuse toolchain)}) (selected "normal")
  expectVerdicts [H.Caught, H.Survived, H.Caught] fresh
  expectVerdicts [H.Caught, H.Survived, H.Caught] retained
  cacheLog <- Text.pack <$> readFile (output </> "retained/last-candidate-build.stdout.log")
  unless ("content cache: hit" `Text.isInfixOf` cacheLog) (error "retained candidate did not reuse its compiled input")
  -- Deliberately publish a stale active-input receipt. Verification must fail
  -- before tests, even though GHC actually built a binary.
  stale <- H.runCampaign ((options "stale") {H.buildReuse = Just (contentAddressedReuse toolchain)}) (selected "stale")
  expectVerdicts (replicate 3 H.InfrastructureError) stale
