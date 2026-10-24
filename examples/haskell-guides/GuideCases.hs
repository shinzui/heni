module GuideCases (runExpectations, removeGuard, runHooks, crashFixture, runCrashes) where

import Control.Concurrent (threadDelay)
import Control.Monad (unless)
import Data.Map.Strict qualified as Map
import Data.Text qualified as Text
import GuideSupport
import System.Exit (ExitCode (..), exitWith)
import System.FilePath ((</>))
import System.Posix.Signals (raiseSignal, sigKILL, sigTERM)
import Test.Heni qualified as H
import Test.Heni.Crash (recordCrashProbe)

runExpectations :: FilePath -> FilePath -> FilePath -> FilePath -> IO ()
runExpectations self ghc source output = do
  let rejected = H.Replace (target "Subject.hs") "used < limit" "missingCapacityGuard" 1
      control = definition "unchanged" [] H.Control
      compiler = (definition "expected-rejection" [rejected] (H.BuildRejection 1 "missingCapacityGuard")) {H.test = Nothing}
      semantic = definition "unrelated-build-error" [rejected] diagnostic
      cases = [(control, H.noHooks), (compiler, H.noHooks), (semantic, H.noHooks)]
  result <- H.runCampaign (H.defaultRunOptions source output) (campaign (commands self ghc "normal") cases)
  expectVerdicts [H.Caught, H.Caught, H.UnexpectedBuildFailure] result
  let H.RunResult {H.results, H.status, H.score} = result
      kinds = [kind | H.CaseResult {H.detection = kind} <- results]
  unless
    (kinds == [Just H.ControlPassed, Just H.ExpectedBuildRejection, Nothing] && status == H.RunFailed && score == Nothing)
    (error (show result))

removeGuard :: H.WorkspaceOps -> IO ()
removeGuard ops = do
  let path = target "Subject.hs"
  original <- H.readTarget ops path
  unless (Text.count "used < limit" original == 1) (ioError (userError "expected one capacity guard"))
  H.writeTarget ops path (Text.replace "used < limit" "True" original)
  H.createTarget ops (target "hook-note.txt") "The consumer removed its capacity guard.\n"
  H.deleteTarget ops (target "hook-note.txt") "The consumer removed its capacity guard.\n"

runHooks :: FilePath -> FilePath -> FilePath -> FilePath -> IO ()
runHooks self ghc source output = do
  let d = definition "custom-guard" [H.CustomEdit "remove-guard"] diagnostic
      hooks = H.noHooks {H.customEdits = [("remove-guard", removeGuard)]}
      cs = commands self ghc "normal"
  -- A missing registration is rejected before any workspace or command exists.
  case H.mkCampaign cs [(d, H.noHooks)] of
    Left _ -> putStrLn "Missing custom hook rejected before execution."
    Right _ -> error "unregistered custom edit was accepted"
  result <- H.runCampaign (H.defaultRunOptions source output) (campaign cs [(d, hooks)])
  expectVerdicts [H.Caught] result

crashFixture :: String -> IO ()
crashFixture mode = do
  changed <- (== "mutant\n") <$> readFile "mode.txt"
  if not changed
    then pure ()
    else do
      unless (mode == "missing-probe") (recordCrashProbe "operation-reached")
      case mode of
        "good" -> raiseSignal sigTERM
        "missing-probe" -> raiseSignal sigTERM
        "wrong-signal" -> raiseSignal sigKILL
        "numeric-exit" -> exitWith (ExitFailure (128 + fromIntegral sigTERM))
        "timeout" -> threadDelay 3000000
        _ -> error "unknown crash example mode"

runCrashes :: FilePath -> FilePath -> FilePath -> IO ()
runCrashes self source output = do
  let modes = ["good", "missing-probe", "wrong-signal", "numeric-exit", "timeout"]
      cs =
        Map.fromList $
          (commandId "build", selfCommand self ["noop"])
            : [(commandId (Text.pack mode), (selfCommand self ["crash", mode]) {H.budget = checked (H.mkStageBudget 500000)}) | mode <- modes]
      d mode =
        ( definition
            (Text.pack mode)
            [H.Replace (target "mode.txt") "safe\n" "mutant\n" 1]
            (H.CrashProbe (fromIntegral sigTERM) "operation-reached")
        )
          { H.test = Just (commandId (Text.pack mode))
          }
  result <- H.runCampaign (H.defaultRunOptions source output) (campaign cs [(d mode, H.noHooks) | mode <- modes])
  expectVerdicts [H.Caught, H.WrongFailure, H.WrongFailure, H.WrongFailure, H.TimedOut] result
  -- Make the output path easy to use with the report consumer example.
  putStrLn (output </> "report.json")
