-- A separate consumer: imports only the exposed umbrella, never internal modules.
module Consumer (definitions, namedCase, diagnosticCase, buildCase, replayCase, controlCase, crashCase) where

import Data.Set qualified as Set
import Test.Heni

checked :: (Show e) => Either e a -> a
checked = either (error . show) id

baseCase :: CaseDefinition
baseCase =
  CaseDefinition
    (checked (mkCaseId "guard-bypass"))
    "Removing the capacity guard must be detected."
    (Set.singleton "regression")
    [Replace (checked (mkRelativeTarget "src/Capacity.hs")) "used < limit" "True" 1]
    (checked (mkCommandId "build"))
    (Just (checked (mkCommandId "test")))
    (Just "rejects full capacity")
    (NamedTests (Set.singleton "rejects full capacity") NoReplay)
    GenericCommands

namedCase, diagnosticCase, buildCase, replayCase, controlCase, crashCase :: CaseDefinition
namedCase = baseCase
diagnosticCase = changeExpectation (Diagnostic Test 1 "capacity rule violated") baseCase
buildCase = changeExpectation (BuildRejection 1 "unbound variable") baseCase
replayCase = changeExpectation (NamedTests (Set.singleton "rejects full capacity") RequireReplay) baseCase
controlCase = case baseCase of
  CaseDefinition i d ts _ b t s _ mode -> CaseDefinition i d ts [] b t s Control mode
crashCase = changeExpectation (CrashProbe 6 "capacity-probe: native operation reached") baseCase

changeExpectation :: Expectation -> CaseDefinition -> CaseDefinition
changeExpectation e (CaseDefinition i d ts es b t s _ mode) = CaseDefinition i d ts es b t s e mode

-- Four independently authored construction trials, corresponding to RES-1 patterns.
-- These are synthetic classifier inputs, not executed migrations.
definitions :: [CaseDefinition]
definitions = [namedCase, patchCatalogue, generatedCode, diagnosticCase]
  where
    patchCatalogue = case baseCase of
      CaseDefinition _ d ts _ b t s e mode ->
        CaseDefinition
          (checked (mkCaseId "patch-guard"))
          d
          ts
          [Patch "diff --git a/src/Capacity.hs b/src/Capacity.hs\n--- a/src/Capacity.hs\n+++ b/src/Capacity.hs\n@@ -1 +1 @@\n-used < limit\n+True\n"]
          b
          t
          s
          e
          mode
    generatedCode = case baseCase of
      CaseDefinition _ d ts _ b t s e mode ->
        CaseDefinition
          (checked (mkCaseId "generated-guard"))
          d
          ts
          [CustomEdit "regenerate-without-guard"]
          b
          t
          s
          e
          mode
