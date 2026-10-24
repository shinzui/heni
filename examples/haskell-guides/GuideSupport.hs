module GuideSupport where

import Control.Monad (unless)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Test.Heni qualified as H

checked :: (Show e) => Either e a -> a
checked = either (error . show) id

target :: FilePath -> H.RelativeTarget
target = checked . H.mkRelativeTarget

commandId :: Text -> H.CommandId
commandId = checked . H.mkCommandId

selfCommand :: FilePath -> [String] -> H.Command
selfCommand self args =
  H.Command
    self
    ("fixture" : args)
    Set.empty
    Nothing
    []
    (checked (H.mkStageBudget 30000000))
    (H.OutputPolicy 65536)

commands :: FilePath -> FilePath -> String -> Map.Map H.CommandId H.Command
commands self ghc behavior =
  Map.fromList
    [ (commandId "build", selfCommand self ["build", ghc, behavior]),
      (commandId "test", selfCommand self ["test"])
    ]

definition :: Text -> [H.Edit] -> H.Expectation -> H.CaseDefinition
definition ident edits expectation =
  H.CaseDefinition
    (checked (H.mkCaseId ident))
    "Exercise the capacity-boundary contract."
    Set.empty
    edits
    (commandId "build")
    (Just (commandId "test"))
    Nothing
    expectation
    H.GenericCommands

diagnostic :: H.Expectation
diagnostic = H.Diagnostic H.Test 1 "rejects full capacity: FAIL"

guardEdit :: H.Edit
guardEdit = H.Replace (target "Subject.hs") "used < limit" "True" 1

campaign :: Map.Map H.CommandId H.Command -> [(H.CaseDefinition, H.CaseHooks)] -> H.Campaign
campaign cs = checked . H.mkCampaign cs

expectVerdicts :: [H.Verdict] -> H.RunResult -> IO ()
expectVerdicts expected result@H.RunResult {H.results} = do
  let actual = [verdict | H.CaseResult {H.verdict} <- results]
  unless (actual == expected) (error ("Unexpected guide result: " ++ show result))
  print actual
