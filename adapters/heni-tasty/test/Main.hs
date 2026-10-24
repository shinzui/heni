module Main (main) where

import Control.Exception
import Control.Monad (forM_, unless)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import System.Directory qualified as Dir
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.Posix.Temp (mkdtemp)
import System.Process (readProcessWithExitCode)
import System.Timeout (timeout)
import Test.Heni

checked :: (Show e) => Either e a -> a
checked = either (error . show) id

assert' :: String -> Bool -> IO ()
assert' why good = unless good (error why)

main :: IO ()
main = timeout 120000000 checks >>= \case Nothing -> error "adapter integration watchdog"; Just () -> pure ()

checks :: IO ()
checks = bracket (Dir.getTemporaryDirectory >>= \p -> mkdtemp (p </> "heni-tasty-")) Dir.removePathForcibly $ \root -> do
  let source = root </> "source"
      exe = "heni-tasty-fixture"
      bid = checked (mkCommandId "build")
      tid = checked (mkCommandId "test")
      cid = checked (mkCaseId "named")
      command args = Command exe args Set.empty Nothing [] (checked (mkStageBudget 5000000)) (OutputPolicy 4096)
      definition mode selector intended replay =
        CaseDefinition
          cid
          "framework evidence"
          Set.empty
          [Replace (checked (mkRelativeTarget "input")) "anchor" mode 1]
          bid
          (Just tid)
          selector
          (NamedTests (Set.singleton intended) replay)
          StructuredTestsV1
      run name def hooks args =
        runCampaign
          (defaultRunOptions source (root </> name))
          (checked (mkCampaign (Map.fromList [(bid, command ["--heni-build"]), (tid, command args)]) [(def, hooks)]))
      is verdict RunResult {results = [CaseResult {verdict = actual}]} = actual == verdict
      is _ _ = False
  Dir.createDirectory source
  writeFile (source </> "input") "anchor"
  old <- Dir.getCurrentDirectory
  direct <- bracket_ (Dir.setCurrentDirectory source) (Dir.setCurrentDirectory old) (readProcessWithExitCode exe [] "")
  assert' "ordinary direct execution" (case direct of (ExitSuccess, _, _) -> True; _ -> False)
  forM_ [("intended", Caught), ("wrong", WrongFailure), ("setup", InfrastructureError)] $ \(mode, expected) -> do
    result <- run mode (definition (Text.pack mode) Nothing "suite/intended" NoReplay) noHooks []
    assert' (mode ++ ": " ++ show result) (is expected result)
  empty <- run "empty" (definition "intended" (Just "absent") "suite/intended" NoReplay) noHooks []
  assert' "empty selection baseline prevents candidate" (is NotRun empty)
  filtered <- run "filtered" (definition "intended" (Just "intended") "suite/intended" NoReplay) noHooks ["--pattern", "intended"]
  assert' ("native and Heni filters: " ++ show filtered) (is Caught filtered)

  writeFile (root </> "manifest.json") "{\"schemaVersion\": 1, \"sourceRoot\": \"source\", \"commands\": {\"build\": {\"executable\": \"heni-tasty-fixture\", \"arguments\": [\"--heni-build\"]}, \"test\": {\"executable\": \"heni-tasty-fixture\"}}, \"cases\": [{\"id\": \"named\", \"description\": \"framework evidence\", \"build\": \"build\", \"test\": \"test\", \"adapter\": \"heni-v1\", \"edits\": [{\"kind\": \"replace\", \"path\": \"input\", \"old\": \"anchor\", \"new\": \"intended\"}], \"expect\": {\"kind\": \"named-tests\", \"failures\": [\"suite/intended\"]}}]}"
  cli <- readProcessWithExitCode "heni" ["run", root </> "manifest.json", "--output", root </> "cli", "--json"] ""
  assert' ("CLI adapter parity: " ++ show cli) (case cli of (ExitSuccess, _, _) -> True; _ -> False)
  putStrLn "tasty direct execution and named subprocess evidence passed"
