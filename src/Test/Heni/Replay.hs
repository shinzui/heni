-- | Opaque replay tokens belong to the producing framework, not a universal DSL.
module Test.Heni.Replay (replayCommand) where

import Data.Text qualified as Text
import Test.Heni.Command
import Test.Heni.Expectation

-- | Reuse the candidate test command with the exact token and generator contract.
-- A typed CaseHooks replayBuilder may replace this for another framework.
replayCommand :: ReplayEvidence -> Command -> Command
replayCommand ReplayEvidence {token, generator} (Command exe args sensitive working env budget output) =
  Command
    exe
    args
    sensitive
    working
    (("HENI_REPLAY_TOKEN", Text.unpack token) : ("HENI_REPLAY_GENERATOR", Text.unpack generator) : filter (\(key, _) -> key `notElem` ["HENI_REPLAY_TOKEN", "HENI_REPLAY_GENERATOR"]) env)
    budget
    output
