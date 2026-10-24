-- | Portable commands and validated budgets. Commands run without shell expansion.
module Test.Heni.Command
  ( CommandId,
    mkCommandId,
    commandIdText,
    StageBudget,
    mkStageBudget,
    budgetMicroseconds,
    Stage (..),
    ProcessOutcome (..),
    OutputPolicy (..),
    Command (..),
    validateCommand,
  )
where

import Data.Set qualified as Set
import Test.Heni.Internal.Model

-- | Validate launch-independent constraints. Environment names must be unique.
validateCommand :: Command -> Either ConfigError ()
validateCommand Command {executable, arguments, sensitiveArguments, environment, output = OutputPolicy {limitBytes}}
  | null executable || '\0' `elem` executable = bad "executable" "expected an executable without NUL"
  | any (elem '\0') arguments = bad "arguments" "NUL in argument"
  | any (\i -> i < 0 || i >= length arguments) (Set.toList sensitiveArguments) = bad "sensitiveArguments" "argument index is out of range"
  | limitBytes <= 0 = bad "output.limitBytes" "expected a positive output limit"
  | any (\(k, v) -> null k || any (`elem` k) ['=', '\0'] || '\0' `elem` v) environment = bad "environment" "invalid environment entry"
  | length (map fst environment) /= length (unique (map fst environment)) = bad "environment" "duplicate environment key"
  | otherwise = Right ()
  where
    bad f m = Left (ConfigError f m)
    unique [] = []
    unique (x : xs) = x : unique (filter (/= x) xs)
