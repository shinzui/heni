-- | Explicit version-one wire vocabulary. No Generic-derived compatibility.
module Test.Heni.Internal.Codec where

import Control.Monad (unless)
import Data.Aeson
import Data.Aeson.Decoding.ByteString (bsToTokens)
import Data.Aeson.Decoding.Tokens
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (Parser)
import Data.ByteString qualified as BS
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Heni.Case (validateCase)
import Test.Heni.Command (validateCommand)
import Test.Heni.Internal.Model
import Test.Heni.Result (summarizeRun)

-- | Validate the original token stream before Aeson's map conversion can erase
-- duplicate keys. Escaped spellings are compared as decoded keys at every depth.
decodeJSON :: BS.ByteString -> Either String Value
decodeJSON bytes = do
  leftover <- checkTokens 0 (bsToTokens bytes)
  unless (BS.all (`elem` [9, 10, 13, 32]) leftover) (Left "trailing non-whitespace after JSON value")
  eitherDecodeStrict bytes

checkTokens :: Int -> Tokens k String -> Either String k
checkTokens depth _ | depth > 128 = Left "JSON nesting exceeds 128 levels"
checkTokens _ (TkLit _ k) = Right k
checkTokens _ (TkText _ k) = Right k
checkTokens _ (TkNumber _ k) = Right k
checkTokens depth (TkArrayOpen array) = checkArray (depth + 1) array
checkTokens depth (TkRecordOpen record) = checkRecord (depth + 1) Set.empty record
checkTokens _ (TkErr message) = Left message

checkArray :: Int -> TkArray k String -> Either String k
checkArray depth (TkItem value) = checkTokens depth value >>= checkArray depth
checkArray _ (TkArrayEnd k) = Right k
checkArray _ (TkArrayErr message) = Left message

checkRecord :: Int -> Set.Set Key -> TkRecord k String -> Either String k
checkRecord depth seen (TkPair key value)
  | key `Set.member` seen = Left ("duplicate JSON object key: " ++ Key.toString key)
  | otherwise = checkTokens depth value >>= checkRecord depth (Set.insert key seen)
checkRecord _ _ (TkRecordEnd k) = Right k
checkRecord _ _ (TkRecordErr message) = Left message

strictObject :: String -> [Key] -> (Object -> Parser a) -> Value -> Parser a
strictObject label allowed f = withObject label $ \o -> do
  unless (all (`elem` allowed) (KM.keys o)) (fail (label ++ ": unknown keys " ++ show (filter (`notElem` allowed) (KM.keys o))))
  f o

checked :: (Show e) => Either e a -> Parser a
checked = either (fail . show) pure

enumValue :: (Eq a) => [(Text, a)] -> a -> Value
enumValue table a = case [name | (name, b) <- table, a == b] of
  name : _ -> String name
  [] -> error "internal wire enum table is incomplete"

enumParser :: [(Text, a)] -> Value -> Parser a
enumParser table = withText "enum" (\name -> maybe (fail ("unknown value: " ++ Text.unpack name)) pure (lookup name table))

stageTable :: [(Text, Stage)]
stageTable = [("setup", Setup), ("build", Build), ("test", Test), ("replay", Replay), ("teardown", Teardown)]

verdicts :: [(Text, Verdict)]
verdicts = [("caught", Caught), ("survived", Survived), ("invalid-mutation", InvalidMutation), ("uncovered", Uncovered), ("unexpected-build-failure", UnexpectedBuildFailure), ("wrong-failure", WrongFailure), ("timed-out", TimedOut), ("infrastructure-error", InfrastructureError), ("not-run", NotRun)]

detections :: [(Text, DetectionKind)]
detections = [("semantic-named", SemanticNamed), ("generic-diagnostic", GenericDiagnostic), ("expected-build-rejection", ExpectedBuildRejection), ("explicit-crash", ExplicitCrash), ("control-passed", ControlPassed)]

statuses :: [(Text, RunStatus)]
statuses = [("passed", RunPassed), ("failed", RunFailed), ("untrustworthy", RunUntrustworthy), ("interrupted", RunInterrupted)]

nullable :: (a -> Value) -> Maybe a -> Value
nullable = maybe Null

parseNullable :: (Value -> Parser a) -> Value -> Parser (Maybe a)
parseNullable _ Null = pure Nothing
parseNullable f v = Just <$> f v

commandJSON :: Command -> Value
commandJSON Command {executable, arguments, sensitiveArguments, workingDirectory, environment, budget, output = OutputPolicy {limitBytes}} =
  object
    [ "executable" .= executable,
      "arguments" .= arguments,
      "sensitiveArguments" .= Set.toAscList sensitiveArguments,
      "workingDirectory" .= fmap targetPath workingDirectory,
      "environment" .= object [Key.fromString k .= v | (k, v) <- environment],
      "timeoutMicroseconds" .= budgetMicroseconds budget,
      "outputLimitBytes" .= limitBytes
    ]

parseCommand :: Value -> Parser Command
parseCommand = strictObject "command" ["executable", "arguments", "sensitiveArguments", "workingDirectory", "environment", "timeoutMicroseconds", "outputLimitBytes"] $ \o -> do
  executable <- o .: "executable"
  arguments <- o .:? "arguments" .!= []
  sensitiveArguments <- o .:? "sensitiveArguments" .!= [] >>= uniqueSet
  relative <- o .:? "workingDirectory"
  workingDirectory <- traverse (checked . mkRelativeTarget) relative
  env <- o .:? "environment" .!= KM.empty
  environment <- mapM (\(k, v) -> (,) (Key.toString k) <$> parseJSON v) (KM.toList env)
  budget <- o .: "timeoutMicroseconds" >>= checked . mkStageBudget
  output <- OutputPolicy <$> o .:? "outputLimitBytes" .!= 1048576
  let command = Command {executable, arguments, sensitiveArguments, workingDirectory, environment, budget, output}
  checked (validateCommand command)
  pure command

editJSON :: Edit -> Value
editJSON (Replace p old new n) = object ["kind" .= String "replace", "path" .= targetPath p, "old" .= old, "new" .= new, "occurrences" .= n]
editJSON (Create p content) = object ["kind" .= String "create", "path" .= targetPath p, "content" .= content]
editJSON (Delete p content) = object ["kind" .= String "delete", "path" .= targetPath p, "expected" .= content]
editJSON (Patch content) = object ["kind" .= String "patch", "content" .= content]
editJSON (CustomEdit key) = object ["kind" .= String "custom", "key" .= key]

parseEdit :: Value -> Parser Edit
parseEdit value =
  withObject
    "edit"
    ( \o ->
        o .: "kind" >>= \(kind :: Text) -> case kind of
          "replace" -> strictObject "replace" ["kind", "path", "old", "new", "occurrences"] (\x -> Replace <$> (x .: "path" >>= checked . mkRelativeTarget) <*> x .: "old" <*> x .: "new" <*> x .:? "occurrences" .!= 1) value
          "create" -> strictObject "create" ["kind", "path", "content"] (\x -> Create <$> (x .: "path" >>= checked . mkRelativeTarget) <*> x .: "content") value
          "delete" -> strictObject "delete" ["kind", "path", "expected"] (\x -> Delete <$> (x .: "path" >>= checked . mkRelativeTarget) <*> x .: "expected") value
          "patch" -> strictObject "patch" ["kind", "content"] (\x -> Patch <$> x .: "content") value
          "custom" -> strictObject "custom" ["kind", "key"] (\x -> CustomEdit <$> x .: "key") value
          _ -> fail "unknown edit kind"
    )
    value

expectationJSON :: Expectation -> Value
expectationJSON (NamedTests ids policy) = object ["kind" .= String "named-tests", "failures" .= Set.toAscList ids, "replayRequired" .= (policy == RequireReplay)]
expectationJSON (Diagnostic stage code witness) = object ["kind" .= String "diagnostic", "stage" .= enumValue stageTable stage, "exitCode" .= code, "outputContains" .= witness]
expectationJSON (BuildRejection code witness) = object ["kind" .= String "build-rejection", "exitCode" .= code, "outputContains" .= witness]
expectationJSON (CrashProbe signal probe) = object ["kind" .= String "crash", "signal" .= signal, "probe" .= probe]
expectationJSON Control = object ["kind" .= String "control"]

parseExpectation :: Value -> Parser Expectation
parseExpectation value =
  withObject
    "expectation"
    ( \o ->
        o .: "kind" >>= \(kind :: Text) -> case kind of
          "named-tests" -> strictObject "named-tests" ["kind", "failures", "replayRequired"] (\x -> NamedTests <$> (x .: "failures" >>= uniqueSet) <*> ((\b -> if b then RequireReplay else NoReplay) <$> (x .:? "replayRequired" .!= False))) value
          "diagnostic" -> strictObject "diagnostic" ["kind", "stage", "exitCode", "outputContains"] (\x -> Diagnostic <$> (x .: "stage" >>= enumParser stageTable) <*> x .: "exitCode" <*> x .: "outputContains") value
          "build-rejection" -> strictObject "build-rejection" ["kind", "exitCode", "outputContains"] (\x -> BuildRejection <$> x .: "exitCode" <*> x .: "outputContains") value
          "crash" -> strictObject "crash" ["kind", "signal", "probe"] (\x -> CrashProbe <$> x .: "signal" <*> x .: "probe") value
          "control" -> strictObject "control" ["kind"] (const (pure Control)) value
          _ -> fail "unknown expectation kind"
    )
    value

uniqueSet :: (Ord a) => [a] -> Parser (Set.Set a)
uniqueSet xs = let s = Set.fromList xs in if Set.size s == length xs then pure s else fail "duplicate set member"

caseJSON :: CaseDefinition -> Value
caseJSON CaseDefinition {caseId, description, tags, edits, build, test, selector, expectation} =
  object
    [ "id" .= caseIdText caseId,
      "description" .= description,
      "tags" .= Set.toAscList tags,
      "edits" .= map editJSON edits,
      "build" .= commandIdText build,
      "test" .= fmap commandIdText test,
      "selector" .= selector,
      "expect" .= expectationJSON expectation
    ]

parseCase :: Value -> Parser CaseDefinition
parseCase = strictObject "case" ["id", "description", "tags", "edits", "build", "test", "selector", "expect"] $ \o -> do
  caseId <- o .: "id" >>= checked . mkCaseId
  description <- o .: "description"
  tags <- o .:? "tags" .!= [] >>= uniqueSet
  edits <- o .:? "edits" .!= [] >>= mapM parseEdit
  build <- o .: "build" >>= checked . mkCommandId
  test <- o .:? "test" >>= traverse (checked . mkCommandId)
  selector <- o .:? "selector"
  expectation <- o .: "expect" >>= parseExpectation
  let definition = CaseDefinition {caseId, description, tags, edits, build, test, selector, expectation}
  checked (validateCase definition)
  pure definition

outcomeJSON :: ProcessOutcome -> Value
outcomeJSON (Exited code) = object ["kind" .= String "exit", "code" .= code]
outcomeJSON (Signaled signal) = object ["kind" .= String "signal", "signal" .= signal]
outcomeJSON Timeout = object ["kind" .= String "timeout"]
outcomeJSON Cancelled = object ["kind" .= String "cancelled"]
outcomeJSON (LaunchFailed message) = object ["kind" .= String "launch-failed", "message" .= message]

parseOutcome :: Value -> Parser ProcessOutcome
parseOutcome value =
  withObject
    "outcome"
    ( \o ->
        o .: "kind" >>= \(kind :: Text) -> case kind of
          "exit" -> strictObject "exit" ["kind", "code"] (\x -> do n <- x .: "code"; if n < 0 then fail "negative normal exit" else pure (Exited n)) value
          "signal" -> strictObject "signal" ["kind", "signal"] (\x -> do n <- x .: "signal"; if n <= 0 then fail "nonpositive signal" else pure (Signaled n)) value
          "timeout" -> strictObject "timeout" ["kind"] (const (pure Timeout)) value
          "cancelled" -> strictObject "cancelled" ["kind"] (const (pure Cancelled)) value
          "launch-failed" -> strictObject "launch-failed" ["kind", "message"] (\x -> LaunchFailed <$> x .: "message") value
          _ -> fail "unknown process outcome"
    )
    value

selectionJSON :: SelectionEvidence -> Value
selectionJSON SelectionEvidence {discovered, selected, executed, executedIds, failedIds, skippedIds, setupErrors} =
  object
    [ "discovered" .= discovered,
      "selected" .= selected,
      "executed" .= executed,
      "executedIds" .= Set.toAscList executedIds,
      "failedIds" .= Set.toAscList failedIds,
      "skippedIds" .= Set.toAscList skippedIds,
      "setupErrors" .= setupErrors
    ]

parseSelection :: Value -> Parser SelectionEvidence
parseSelection = strictObject "selection" ["discovered", "selected", "executed", "executedIds", "failedIds", "skippedIds", "setupErrors"] $ \o ->
  SelectionEvidence
    <$> o .: "discovered"
    <*> o .: "selected"
    <*> o .: "executed"
    <*> (o .: "executedIds" >>= uniqueSet)
    <*> (o .: "failedIds" >>= uniqueSet)
    <*> (o .: "skippedIds" >>= uniqueSet)
    <*> o .: "setupErrors"

replayJSON :: ReplayEvidence -> Value
replayJSON ReplayEvidence {token, generator, failures} = object ["token" .= token, "generator" .= generator, "failures" .= Set.toAscList failures]

parseReplay :: Value -> Parser ReplayEvidence
parseReplay = strictObject "replay" ["token", "generator", "failures"] $ \o -> ReplayEvidence <$> o .: "token" <*> o .: "generator" <*> (o .: "failures" >>= uniqueSet)

stageJSON :: StageEvidence -> Value
stageJSON StageEvidence {stage, outcome, transcript, truncated, selection, replay, durationSeconds, logPaths} =
  object
    [ "stage" .= enumValue stageTable stage,
      "outcome" .= outcomeJSON outcome,
      "witnesses" .= transcript,
      "evidenceUnavailable" .= truncated,
      "selection" .= selectionJSON selection,
      "replay" .= nullable replayJSON replay,
      "durationSeconds" .= durationSeconds,
      "logPaths" .= logPaths
    ]

parseStage :: Value -> Parser StageEvidence
parseStage = strictObject "stage" ["stage", "outcome", "witnesses", "evidenceUnavailable", "selection", "replay", "durationSeconds", "logPaths"] $ \o -> do
  stage <- o .: "stage" >>= enumParser stageTable
  outcome <- o .: "outcome" >>= parseOutcome
  transcript <- o .: "witnesses"
  truncated <- o .: "evidenceUnavailable"
  selection <- o .: "selection" >>= parseSelection
  replay <- o .: "replay" >>= parseNullable parseReplay
  durationSeconds <- o .: "durationSeconds"
  unless (durationSeconds >= 0 && not (isInfinite durationSeconds || isNaN durationSeconds)) (fail "invalid duration")
  logPaths <- o .: "logPaths"
  mapM_ (checked . mkRelativeTarget) logPaths
  pure StageEvidence {stage, outcome, transcript, truncated, selection, replay, durationSeconds, logPaths}

baselineJSON :: BaselineEvidence -> Value
baselineJSON BaselinePassed = object ["kind" .= String "passed"]
baselineJSON BaselineUnavailable = object ["kind" .= String "unavailable"]
baselineJSON (BaselineFailed message) = object ["kind" .= String "failed", "message" .= message]

parseBaseline :: Value -> Parser BaselineEvidence
parseBaseline = strictObject "baseline" ["kind", "message"] $ \o ->
  o .: "kind" >>= \(kind :: Text) -> case kind of
    "passed" -> pure BaselinePassed
    "unavailable" -> pure BaselineUnavailable
    "failed" -> BaselineFailed <$> o .: "message"
    _ -> fail "unknown baseline status"

mutationJSON :: MutationEvidence -> Value
mutationJSON Changed = object ["kind" .= String "changed"]
mutationJSON Unchanged = object ["kind" .= String "unchanged"]
mutationJSON (EditRejected message) = object ["kind" .= String "rejected", "message" .= message]

parseMutation :: Value -> Parser MutationEvidence
parseMutation = strictObject "mutation" ["kind", "message"] $ \o ->
  o .: "kind" >>= \(kind :: Text) -> case kind of
    "changed" -> pure Changed
    "unchanged" -> pure Unchanged
    "rejected" -> EditRejected <$> o .: "message"
    _ -> fail "unknown mutation status"

evidenceJSON :: CaseEvidence -> Value
evidenceJSON CaseEvidence {baseline, mutation, stages, infrastructureErrors, cleanupErrors, stopped} =
  object
    [ "baseline" .= baselineJSON baseline,
      "mutation" .= mutationJSON mutation,
      "stages" .= map stageJSON stages,
      "infrastructureErrors" .= infrastructureErrors,
      "cleanupErrors" .= cleanupErrors,
      "stopped" .= stopped
    ]

parseEvidence :: Value -> Parser CaseEvidence
parseEvidence = strictObject "case evidence" ["baseline", "mutation", "stages", "infrastructureErrors", "cleanupErrors", "stopped"] $ \o ->
  CaseEvidence
    <$> (o .: "baseline" >>= parseBaseline)
    <*> (o .: "mutation" >>= parseMutation)
    <*> (o .: "stages" >>= mapM parseStage)
    <*> o .: "infrastructureErrors"
    <*> o .: "cleanupErrors"
    <*> o .: "stopped"

caseResultJSON :: CaseResult -> Value
caseResultJSON CaseResult {caseId, verdict, detection, semantic, control, reason, evidence} =
  object
    [ "id" .= caseIdText caseId,
      "verdict" .= enumValue verdicts verdict,
      "detection" .= nullable (enumValue detections) detection,
      "semantic" .= semantic,
      "control" .= control,
      "reason" .= reason,
      "evidence" .= evidenceJSON evidence
    ]

parseCaseResult :: Value -> Parser CaseResult
parseCaseResult = strictObject "case result" ["id", "verdict", "detection", "semantic", "control", "reason", "evidence"] $ \o ->
  CaseResult
    <$> (o .: "id" >>= checked . mkCaseId)
    <*> (o .: "verdict" >>= enumParser verdicts)
    <*> (o .: "detection" >>= parseNullable (enumParser detections))
    <*> o .: "semantic"
    <*> o .: "control"
    <*> o .: "reason"
    <*> (o .: "evidence" >>= parseEvidence)

failureJSON :: RunFailure -> Value
failureJSON (BaselineFailure ids why) = object ["kind" .= String "baseline", "affected" .= map caseIdText ids, "message" .= why]
failureJSON (ControlFailure i why) = object ["kind" .= String "control", "id" .= caseIdText i, "message" .= why]
failureJSON (RunInfrastructure why) = object ["kind" .= String "infrastructure", "message" .= why]
failureJSON (Interrupted why) = object ["kind" .= String "interrupted", "message" .= why]

parseFailure :: Value -> Parser RunFailure
parseFailure = strictObject "run failure" ["kind", "affected", "id", "message"] $ \o ->
  o .: "kind" >>= \(kind :: Text) -> case kind of
    "baseline" -> BaselineFailure <$> (o .: "affected" >>= mapM (checked . mkCaseId)) <*> o .: "message"
    "control" -> ControlFailure <$> (o .: "id" >>= checked . mkCaseId) <*> o .: "message"
    "infrastructure" -> RunInfrastructure <$> o .: "message"
    "interrupted" -> Interrupted <$> o .: "message"
    _ -> fail "unknown run failure"

scoreJSON :: SemanticScore -> Value
scoreJSON (SemanticScore caught total complete) = object ["caught" .= caught, "total" .= total, "complete" .= complete]

parseScore :: Value -> Parser SemanticScore
parseScore = strictObject "score" ["caught", "total", "complete"] $ \o -> SemanticScore <$> o .: "caught" <*> o .: "total" <*> o .: "complete"

resultJSON :: RunResult -> Value
resultJSON RunResult {selectedIds, results, failures, status, score} =
  object
    [ "selectedIds" .= map caseIdText selectedIds,
      "cases" .= map caseResultJSON results,
      "failures" .= map failureJSON failures,
      "status" .= enumValue statuses status,
      "semanticScore" .= nullable scoreJSON score
    ]

parseResult :: Value -> Parser RunResult
parseResult = strictObject "run result" ["selectedIds", "cases", "failures", "status", "semanticScore"] $ \o -> do
  selected <- o .: "selectedIds" >>= mapM (checked . mkCaseId) >>= checked . mkSelectedCases
  cases <- o .: "cases" >>= mapM parseCaseResult
  failures <- o .: "failures" >>= mapM parseFailure
  status <- o .: "status" >>= enumParser statuses
  score <- o .: "semanticScore" >>= parseNullable parseScore
  result <- checked (summarizeRun selected cases failures)
  let RunResult {status = actualStatus, score = actualScore} = result
  unless (actualStatus == status && actualScore == score) (fail "stored summary contradicts selected ledger")
  pure result
