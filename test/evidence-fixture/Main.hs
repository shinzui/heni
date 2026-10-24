module Main (main) where

import Control.Concurrent (threadDelay)
import Data.ByteString qualified as BS
import Data.List (isInfixOf)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import System.Environment (getArgs, lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.IO
import System.Posix.Process (getProcessID)
import System.Posix.Signals
import Test.Heni.Adapter
import Test.Heni.Crash
import Test.Heni.Expectation (ReplayEvidence (..))

main :: IO ()
main = do
  hSetBuffering stdout NoBuffering
  hSetBuffering stderr NoBuffering
  getArgs >>= \case
    ["exit", "0"] -> pure ()
    ["protocol", path, mode] -> protocolFixture path mode
    ["crash", path, mode] -> crashFixture path mode
    _ -> error "unknown evidence fixture mode"

protocolFixture :: FilePath -> String -> IO ()
protocolFixture path mode = do
  mutated <- isInfixOf "mutant" <$> readFile path
  selector <- fmap Text.pack <$> lookupEnv "HENI_SELECTOR"
  currentStage <- lookupEnv "HENI_STAGE"
  let allIds = ["suite/intended", "suite/other"]
      selected = maybe allIds (\s -> filter (Text.isInfixOf s) allIds) selector
      observation ident
        | not mutated = TestPassed ident
        | ident == "suite/intended" && mode == "skipped" = TestSkipped ident
        | ident == "suite/intended" && mode == "setup" = TestSetupFailed ident "fixture setup failed"
        | ident == "suite/other" && mode == "wrong" = TestFailed ident
        | ident == "suite/intended" && mode /= "wrong" = TestFailed ident
        | otherwise = TestPassed ident
      observations = map observation selected
      failed = Set.fromList [ident | TestFailed ident <- observations]
  token <- maybe "fixture-token" Text.pack <$> lookupEnv "HENI_REPLAY_TOKEN"
  generator <- maybe "fixture-generator" Text.pack <$> lookupEnv "HENI_REPLAY_GENERATOR"
  let replay = if mutated && mode `elem` ["replay", "replay-timeout"] then Just (ReplayEvidence token generator failed) else Nothing
      producer = if mutated && mode == "version" then "fixture/v2" else "fixture/v1"
      suite = SuiteEvidence producer (Just allIds) selected observations [] replay ["counterexample"]
  currentEvidenceAttempt
    >>= mapM_
      ( \attempt -> do
          let destination = if mutated && mode == "stale" then case attempt of EvidenceAttempt root dir _ ident stage role -> EvidenceAttempt root dir "stale-run" ident stage role else attempt
          emitSuite destination suite
          if mutated
            then case mode of
              "partial" -> do
                bytes <- BS.readFile (evidencePath attempt)
                BS.writeFile (evidencePath attempt) (BS.intercalate "\n" (init (init (BS.split 10 bytes))))
              "counts" -> do
                bytes <- BS.readFile (evidencePath attempt)
                let text = Text.replace "\"executed\":2" "\"executed\":9" (Text.decodeUtf8 bytes)
                BS.writeFile (evidencePath attempt) (Text.encodeUtf8 text)
              _ -> pure ()
            else pure ()
      )
  if mutated && mode == "replay-timeout" && currentStage == Just "replay" then threadDelay 30000000 else pure ()
  if any (\case TestFailed {} -> True; TestSetupFailed {} -> True; _ -> False) observations then exitWith (ExitFailure 1) else pure ()

crashFixture :: FilePath -> String -> IO ()
crashFixture path mode = do
  mutated <- isInfixOf "mutant" <$> readFile path
  if not mutated
    then recordCrashProbe "operation-reached"
    else do
      case mode of
        "missing" -> putStrLn "operation-reached"
        "stale" -> currentEvidenceAttempt >>= mapM_ (\case EvidenceAttempt root dir _ ident stage role -> writeCrashProbe (EvidenceAttempt root dir "stale-run" ident stage role) "operation-reached")
        _ -> recordCrashProbe "operation-reached"
      case mode of
        "timeout" -> threadDelay 30000000
        "exit" -> exitWith (ExitFailure (128 + fromIntegral sigABRT))
        "wrong-signal" -> getProcessID >>= signalProcess sigTERM
        _ -> getProcessID >>= signalProcess sigABRT
