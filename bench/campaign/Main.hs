module Main (main) where

import Control.Exception
import Data.Aeson
import Data.ByteString.Lazy.Char8 qualified as LBS
import Data.IORef
import Data.Version (showVersion)
import Definitions (exampleCampaign)
import GHC.Clock (getMonotonicTimeNSec)
import Paths_heni (getDataFileName)
import System.Directory qualified as Dir
import System.Environment (getArgs)
import System.FilePath (takeDirectory, (</>))
import System.Info qualified as Platform
import System.Posix.Temp (mkdtemp)
import Test.Heni
import Text.Read (readMaybe)

modify_ :: IORef a -> (a -> a) -> IO ()
modify_ ref f = atomicModifyIORef' ref (\x -> (f x, ()))

main :: IO ()
main = do
  args <- getArgs
  let parse [] = (1, "fresh")
      parse ["--workers", n, "--mode", mode] | Just count <- readMaybe n, count > 0, count <= 256, mode `elem` ["fresh", "reuse"] = (count, mode)
      parse _ = error "use --workers N --mode fresh|reuse"
      (jobs, mode) = parse args
  source <- getDataFileName "examples/minimal/heni-minimal-fixture.cabal" >>= pure . takeDirectory
  bracket (Dir.getTemporaryDirectory >>= \p -> mkdtemp (p </> "heni-cabal-bench-")) Dir.removePathForcibly $ \root -> do
    totals <- newIORef (0 :: Int, 0 :: Double, 0 :: Int, 0 :: Int)
    let observe (CaseStarted _) = modify_ totals (\(baselines, buildTime, active, peak) -> (baselines, buildTime, active + 1, max peak (active + 1)))
        observe (CaseFinished _) = modify_ totals (\(b, t, a, p) -> (b, t, a - 1, p))
        observe (StageFinished _ role StageEvidence {stage = Build, durationSeconds}) = modify_ totals (\(b, t, a, p) -> (b + if role == "baseline" then 1 else 0, t + durationSeconds, a, p))
        observe _ = pure ()
        options = (defaultRunOptions source (root </> "run")) {workers = jobs, progress = observe, reusePolicy = if mode == "reuse" then ReuseBaselines "current GHC/Cabal and released fixture dependencies; no external state" Nothing else Fresh}
    start <- getMonotonicTimeNSec
    result <- runCampaign options exampleCampaign
    end <- getMonotonicTimeNSec
    (baselines, buildTime, _, peak) <- readIORef totals
    LBS.putStrLn
      ( encode
          ( object
              [ "workload" .= String "three real Cabal cases: caught, survivor, compiler error",
                "mode" .= mode,
                "workers" .= jobs,
                "perBuildJobs" .= (1 :: Int),
                "peakCaseConcurrency" .= peak,
                "baselineBuildInvocations" .= baselines,
                "elapsedSeconds" .= (fromIntegral (end - start) / 1e9 :: Double),
                "sumBuildStageSeconds" .= buildTime,
                "platform" .= object ["os" .= Platform.os, "arch" .= Platform.arch, "compiler" .= Platform.compilerName, "compilerVersion" .= showVersion Platform.compilerVersion],
                "result" .= runResultJSON result
              ]
          )
      )
