-- | Case definitions and validated portable identities.
module Test.Heni.Case
  ( CaseId,
    mkCaseId,
    caseIdText,
    RelativeTarget,
    mkRelativeTarget,
    targetPath,
    SelectedCases,
    mkSelectedCases,
    selectedCaseIds,
    ConfigError (..),
    CaseDefinition (..),
    Edit (..),
    CaseHooks (..),
    WorkspaceOps (..),
    noHooks,
    validateCase,
  )
where

import Data.Set qualified as Set
import Data.Text qualified as Text
import Test.Heni.Internal.Model

-- | Reject invalid expectations and edits before invoking any command.
validateCase :: CaseDefinition -> Either ConfigError ()
validateCase CaseDefinition {description, edits, test, expectation, selector}
  | Text.null (Text.strip description) = bad "description" "expected an explanation of the fault"
  | maybe False (Text.null . Text.strip) selector = bad "selector" "empty selector"
  | expectation /= Control && null edits = bad "edits" "mutation requires edits"
  | expectation == Control && not (null edits) = bad "edits" "controls must explicitly leave source unchanged"
  | requiresTest expectation && test == Nothing = bad "test" "expectation requires a test command"
  | otherwise = mapM_ validateEdit edits >> validateExpectation expectation
  where
    bad f m = Left (ConfigError f m)
    requiresTest BuildRejection {} = False
    requiresTest (Diagnostic Build _ _) = False
    requiresTest _ = True
    validateEdit (Replace _ old new n)
      | Text.null old || old == new || n <= 0 = bad "edits.replace" "expected nonempty distinct text and a positive exact count"
    validateEdit (Patch p) | Text.null (Text.strip p) = bad "edits.patch" "empty patch"
    validateEdit (CustomEdit k) | Text.null k = bad "edits.custom" "empty hook key"
    validateEdit _ = Right ()
    validateExpectation (NamedTests ids _)
      | Set.null ids || any Text.null ids = bad "expect.namedTests" "expected nonempty named failure set"
    validateExpectation (Diagnostic s code witness)
      | s `notElem` [Build, Test] || code <= 0 || Text.null witness = bad "expect.diagnostic" "expected build/test stage, nonzero exit and witness"
    validateExpectation (BuildRejection code witness)
      | code <= 0 || Text.null witness = bad "expect.buildRejection" "expected nonzero exit and witness"
    validateExpectation (CrashProbe sig probe)
      | sig <= 0 || Text.null probe = bad "expect.crash" "expected positive signal and a case-specific probe"
    validateExpectation _ = Right ()
