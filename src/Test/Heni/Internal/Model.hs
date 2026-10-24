-- | Shared model. Constrained constructors are hidden by the public modules.
module Test.Heni.Internal.Model where

import Data.Char (isAlphaNum, isAscii)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Test.Heni.Internal.Prelude

-- | A field-specific configuration problem, detected before execution.
data ConfigError = ConfigError {field :: !Text, message :: !Text}
  deriving stock (Eq, Show, Generic)

-- | Stable portable case identifier.
newtype CaseId = CaseId Text deriving stock (Eq, Ord, Show, Generic)

-- | Stable portable command identifier.
newtype CommandId = CommandId Text deriving stock (Eq, Ord, Show, Generic)

-- | Slash-separated path relative to a workspace, never a parent or root.
newtype RelativeTarget = RelativeTarget FilePath deriving stock (Eq, Ord, Show, Generic)

-- | Positive wall-clock microseconds, bounded to avoid timer overflow.
newtype StageBudget = StageBudget Int deriving stock (Eq, Ord, Show, Generic)

-- | A nonempty set of selected IDs, preserving the requested order.
newtype SelectedCases = SelectedCases [CaseId] deriving stock (Eq, Show, Generic)

-- | Construct an identifier using ASCII letters, digits, dots, dashes and underscores.
mkCaseId :: Text -> Either ConfigError CaseId
mkCaseId t = CaseId <$> identifier "case.id" t

-- | Construct a reusable command identifier.
mkCommandId :: Text -> Either ConfigError CommandId
mkCommandId t = CommandId <$> identifier "command.id" t

identifier :: Text -> Text -> Either ConfigError Text
identifier f t
  | Text.null t || not (Text.all (\c -> isAscii c && (isAlphaNum c || c `elem` ("-_." :: String))) t) =
      Left (ConfigError f "expected a nonempty portable identifier")
  | otherwise = Right t

-- | Reject traversal, drive syntax, backslashes, empty segments and NULs.
-- Filesystem checks must additionally reject symlinks when opening the target.
mkRelativeTarget :: FilePath -> Either ConfigError RelativeTarget
mkRelativeTarget p
  | null p || any (`elem` p) ['\\', ':', '\0'] || any (`elem` ["", ".", ".."]) parts =
      Left (ConfigError "path" "expected a normalized relative path")
  | otherwise = Right (RelativeTarget p)
  where
    parts = Text.splitOn "/" (Text.pack p)

-- | Budget in microseconds; at most one day for a single stage.
mkStageBudget :: Int -> Either ConfigError StageBudget
mkStageBudget n
  | n > 0 && toInteger n <= 86400000000 = Right (StageBudget n)
  | otherwise = Left (ConfigError "budget" "expected positive microseconds, at most one day")

-- | Reject empty or duplicate selections rather than silently changing their meaning.
mkSelectedCases :: [CaseId] -> Either ConfigError SelectedCases
mkSelectedCases ids
  | null ids = Left (ConfigError "selection" "no cases selected")
  | Set.size (Set.fromList ids) /= length ids = Left (ConfigError "selection" "duplicate case IDs")
  | otherwise = Right (SelectedCases ids)

-- | Underlying portable ID.
caseIdText :: CaseId -> Text
caseIdText (CaseId t) = t

-- | Underlying command ID.
commandIdText :: CommandId -> Text
commandIdText (CommandId t) = t

-- | Path suitable for joining to a verified workspace root.
targetPath :: RelativeTarget -> FilePath
targetPath (RelativeTarget p) = p

-- | Timer argument in microseconds.
budgetMicroseconds :: StageBudget -> Int
budgetMicroseconds (StageBudget n) = n

-- | Requested case order.
selectedCaseIds :: SelectedCases -> [CaseId]
selectedCaseIds (SelectedCases ids) = ids

-- | Independently supervised execution phases.
data Stage = Setup | Build | Test | Replay | Teardown
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)

-- | Exit, signal and runner intervention are deliberately distinct.
data ProcessOutcome = Exited !Int | Signaled !Int | Timeout | Cancelled | LaunchFailed !Text
  deriving stock (Eq, Show, Generic)

-- | Output retention policy. Exceeding the limit cannot prove a diagnostic.
data OutputPolicy = OutputPolicy {limitBytes :: !Int}
  deriving stock (Eq, Show, Generic)

-- | An executable and arguments, with no implicit shell expansion.
data Command = Command
  { executable :: !FilePath,
    arguments :: ![String],
    workingDirectory :: !(Maybe RelativeTarget),
    environment :: ![(String, String)],
    budget :: !StageBudget,
    output :: !OutputPolicy
  }
  deriving stock (Eq, Show, Generic)

-- | Checked text, patch, or registered Haskell edit. Patches are UTF-8 content.
data Edit
  = Replace !RelativeTarget !Text !Text !Int
  | Create !RelativeTarget !Text
  | Delete !RelativeTarget !Text
  | Patch !Text
  | CustomEdit !Text
  deriving stock (Eq, Show, Generic)

-- | A replay token and its exact generator configuration.
data ReplayEvidence = ReplayEvidence
  {token :: !Text, generator :: !Text, failures :: !(Set Text)}
  deriving stock (Eq, Show, Generic)

-- | Whether matching counterexample replay is mandatory.
data ReplayPolicy = NoReplay | RequireReplay
  deriving stock (Eq, Show, Generic)

-- | Expectations declare their evidence strength rather than guessing from output.
data Expectation
  = NamedTests !(Set Text) !ReplayPolicy
  | Diagnostic !Stage !Int !Text
  | BuildRejection !Int !Text
  | CrashProbe !Int !Text
  | Control
  deriving stock (Eq, Show, Generic)

-- | Serializable case data; IO functions are stored separately in 'CaseHooks'.
data CaseDefinition = CaseDefinition
  { caseId :: !CaseId,
    description :: !Text,
    tags :: !(Set Text),
    edits :: ![Edit],
    build :: !CommandId,
    test :: !(Maybe CommandId),
    selector :: !(Maybe Text),
    expectation :: !Expectation
  }
  deriving stock (Eq, Show, Generic)

-- | Operations supplied by the workspace owner. Hooks are trusted IO, not a sandbox.
data WorkspaceOps = WorkspaceOps
  { readTarget :: !(RelativeTarget -> IO Text),
    writeTarget :: !(RelativeTarget -> Text -> IO ()),
    createTarget :: !(RelativeTarget -> Text -> IO ()),
    deleteTarget :: !(RelativeTarget -> Text -> IO ())
  }

-- | Haskell-only extension points. Returned evidence still passes all validity gates.
data CaseHooks = CaseHooks
  { customEdits :: ![(Text, WorkspaceOps -> IO ())],
    customEvidence :: !(Maybe (StageEvidence -> IO (Either Text StageEvidence)))
  }

-- | No custom behavior.
noHooks :: CaseHooks
noHooks = CaseHooks [] Nothing

-- | Counts are optional: unknown is different from zero. IDs identify attribution.
data SelectionEvidence = SelectionEvidence
  { discovered :: !(Maybe Int),
    selected :: !(Maybe Int),
    executed :: !(Maybe Int),
    executedIds :: !(Set Text),
    failedIds :: !(Set Text),
    skippedIds :: !(Set Text),
    setupErrors :: ![Text]
  }
  deriving stock (Eq, Show, Generic)

-- | Generic commands do not invent test counts.
unknownSelection :: SelectionEvidence
unknownSelection = SelectionEvidence Nothing Nothing Nothing Set.empty Set.empty Set.empty []

-- | Observations from a single stage. A truncated output cannot be a witness.
data StageEvidence = StageEvidence
  { stage :: !Stage,
    outcome :: !ProcessOutcome,
    transcript :: !Text,
    truncated :: !Bool,
    selection :: !SelectionEvidence,
    replay :: !(Maybe ReplayEvidence),
    durationSeconds :: !Double,
    logPaths :: ![FilePath]
  }
  deriving stock (Eq, Show, Generic)

-- | Whether edit preconditions and the final byte-change requirement passed.
data MutationEvidence = Changed | Unchanged | EditRejected !Text
  deriving stock (Eq, Show, Generic)

-- | A baseline failure stops the candidate; it is never a mutant kill.
data BaselineEvidence = BaselinePassed | BaselineFailed !Text | BaselineUnavailable
  deriving stock (Eq, Show, Generic)

-- | All validity gates and primary/secondary observations used by the classifier.
data CaseEvidence = CaseEvidence
  { baseline :: !BaselineEvidence,
    mutation :: !MutationEvidence,
    stages :: ![StageEvidence],
    infrastructureErrors :: ![Text],
    cleanupErrors :: ![Text],
    stopped :: !(Maybe Text)
  }
  deriving stock (Eq, Show, Generic)

-- | All nine public case outcomes.
data Verdict
  = Caught
  | Survived
  | InvalidMutation
  | Uncovered
  | UnexpectedBuildFailure
  | WrongFailure
  | TimedOut
  | InfrastructureError
  | NotRun
  deriving stock (Eq, Ord, Show, Enum, Bounded, Generic)

-- | Successful detections and passing controls are tallied separately.
data DetectionKind = SemanticNamed | GenericDiagnostic | ExpectedBuildRejection | ExplicitCrash | ControlPassed
  deriving stock (Eq, Ord, Show, Generic)

-- | Classifier output, retaining every observation and secondary error.
data CaseResult = CaseResult
  { caseId :: !CaseId,
    verdict :: !Verdict,
    detection :: !(Maybe DetectionKind),
    semantic :: !Bool,
    control :: !Bool,
    reason :: !Text,
    evidence :: !CaseEvidence
  }
  deriving stock (Eq, Show, Generic)

-- | Campaign failures keep affected IDs even when no candidate could start.
data RunFailure
  = BaselineFailure ![CaseId] !Text
  | ControlFailure !CaseId !Text
  | RunInfrastructure !Text
  | Interrupted !Text
  deriving stock (Eq, Show, Generic)

-- | CLI-neutral run contract. Infrastructure takes precedence over a failed contract.
data RunStatus = RunPassed | RunFailed | RunUntrustworthy | RunInterrupted
  deriving stock (Eq, Show, Generic)

-- | Only caught and survived semantic mutations contribute to the ratio.
data SemanticScore = SemanticScore {caught :: !Int, total :: !Int, complete :: !Bool}
  deriving stock (Eq, Show, Generic)

-- | Exactly one result per selected ID, in selection order.
data RunResult = RunResult
  { selectedIds :: ![CaseId],
    results :: ![CaseResult],
    failures :: ![RunFailure],
    status :: !RunStatus,
    score :: !(Maybe SemanticScore)
  }
  deriving stock (Eq, Show, Generic)
