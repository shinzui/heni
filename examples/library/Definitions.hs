module Definitions (exampleCampaign) where

import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Test.Heni

checked :: (Show e) => Either e a -> a
checked = either (error . show) id

exampleCampaign :: Campaign
exampleCampaign = checked (mkCampaign commands [(c, noHooks) | c <- cases])
  where
    commandId = checked . mkCommandId
    budget = checked (mkStageBudget 60000000)
    command args = Command "cabal" args Set.empty Nothing [] budget (OutputPolicy 1048576)
    commands =
      Map.fromList
        [ (commandId "build", command ["build", "fixture-test", "--offline", "-j1"]),
          (commandId "test", command ["test", "fixture-test", "--offline", "-j1", "--test-show-details=direct"])
        ]
    target = checked (mkRelativeTarget "src/Capacity.hs")
    define ident old new =
      CaseDefinition
        (checked (mkCaseId ident))
        "The capacity boundary assertion must detect a removed guard."
        (Set.singleton "regression")
        [Replace target old new 1]
        (commandId "build")
        (Just (commandId "test"))
        Nothing
        (Diagnostic Test 1 "rejects full capacity: FAIL")
        GenericCommands
    cases = [define "guard-bypass" "used < limit" "True", define "survivor" "baseline" "mutant", define "compile-error" "used < limit" "missingCapacityGuard"]
