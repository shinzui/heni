module Main (main) where

import Data.Text qualified as Text
import GuideBuild
import GuideCases
import GuideManifest
import GuideReports
import System.Directory qualified as Dir
import System.Environment (getArgs, getExecutablePath)
import System.FilePath ((</>))
import System.Process (readProcess)

main :: IO ()
main =
  getArgs >>= \case
    ["fixture", "noop"] -> pure ()
    ["fixture", "build", ghc, behavior] -> buildFixture ghc behavior
    ["fixture", "test"] -> testFixture
    ["fixture", "crash", mode] -> crashFixture mode
    ["report", path] -> inspectReport path
    [mode, output] -> do
      self <- getExecutablePath
      ghc <- Dir.findExecutable "ghc" >>= maybe (ioError (userError "ghc unavailable")) pure
      version <- readProcess ghc ["--numeric-version"] ""
      let source = "examples/haskell-guides/target"
          toolchain = Text.pack ("guide-content-ghc/v1:" ++ ghc ++ ":") <> Text.strip (Text.pack version)
          run name action = if mode `elem` [name, "all"] then action (if mode == "all" then output </> name else output) else pure ()
      run "expectations" (runExpectations self ghc source)
      run "hooks" (runHooks self ghc source)
      run "crashes" (runCrashes self source)
      run "reuse" (runReuse self ghc toolchain source)
      run "manifest" (runManifest source)
      if mode == "all" then inspectReport (output </> "expectations/report.json") else pure ()
      if mode `elem` ["all", "expectations", "hooks", "crashes", "reuse", "manifest"]
        then putStrLn "Haskell guide expectations verified."
        else ioError (userError "unknown guide mode")
    _ -> ioError (userError "Usage: heni-haskell-guides all|expectations|hooks|crashes|reuse|manifest OUTPUT, or report REPORT.json")
