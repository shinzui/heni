module Main (main) where

import Control.Monad (unless)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Test.Heni

checked :: (Show e) => Either e a -> a
checked = either (error . show) id

main :: IO ()
main = do
  let build = checked (mkCommandId "build")
      test = checked (mkCommandId "test")
      command executable args = Command executable args Set.empty Nothing [] (checked (mkStageBudget 30000000)) (OutputPolicy 4096)
      commands = Map.fromList [(build, command "ghc" ["-v0", "Checker.hs", "-o", "checker"]), (test, command "./checker" [])]
      define cid new = CaseDefinition (checked (mkCaseId cid)) "Remove the intended capacity guard" Set.empty [Replace (checked (mkRelativeTarget "input")) "anchor" new 1] build (Just test) Nothing (Diagnostic Test 1 "capacity rule violated") GenericCommands
      campaign = checked (mkCampaign commands [(define cid value, noHooks) | (cid, value) <- [("caught", "mutant"), ("survivor", "harmless"), ("wrong", "unrelated")]])
  result <- runCampaign (defaultRunOptions "target" "library-results") campaign
  let RunResult {results, status} = result
  unless ([verdict | CaseResult {verdict} <- results] == [Caught, Survived, WrongFailure] && status == RunFailed) (error (show result))
  putStrLn "Standalone library: caught, survived, wrong-failure"
