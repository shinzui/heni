-- | One baseline/candidate lifecycle shared by library users and the CLI.
module Test.Heni.Runner
  ( Campaign,
    mkCampaign,
    campaignCases,
    campaignCommands,
    RunOptions (..),
    defaultRunOptions,
    RunEvent (..),
    ConfigurationFailure (..),
    runCampaign,
  )
where

import Control.Exception hiding (handle)
import Control.Monad (forM_, unless, when)
import Data.Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Data.Version (showVersion)
import System.Directory qualified as Dir
import System.FilePath (takeDirectory)
import System.Info qualified as Platform
import Test.Heni.Adapter qualified as Adapter
import Test.Heni.Case
import Test.Heni.Command
import Test.Heni.Crash qualified as Crash
import Test.Heni.Edit
import Test.Heni.Expectation
import Test.Heni.Internal.Codec
import Test.Heni.Internal.Files (digest, withFinalizer)
import Test.Heni.Process
import Test.Heni.Replay qualified as Replay
import Test.Heni.Report
import Test.Heni.Result
import Test.Heni.Workspace
import Prelude hiding (sequence)

-- | Validated references and portable definitions, with optional trusted IO hooks.
data Campaign = Campaign !(Map.Map CommandId Command) ![(CaseDefinition, CaseHooks)]

-- | Construction rejects all case/command definition errors before execution.
mkCampaign :: Map.Map CommandId Command -> [(CaseDefinition, CaseHooks)] -> Either ConfigError Campaign
mkCampaign commands definitions = do
  _ <- mkSelectedCases [i | (CaseDefinition {caseId = i}, _) <- definitions]
  mapM_ validateCommand (Map.elems commands)
  forM_ definitions $ \(definition@CaseDefinition {caseId, build, test, edits}, CaseHooks {customEdits}) -> do
    validateCase definition
    unless
      (all (`Map.member` commands) (build : maybe [] pure test))
      (Left (ConfigError (caseIdText caseId <> ".commands") "unknown command reference"))
    unless
      (length customEdits == Set.size (Set.fromList (map fst customEdits)))
      (Left (ConfigError (caseIdText caseId <> ".hooks") "duplicate custom edit hook"))
    forM_ edits $ \case
      CustomEdit key | key `notElem` map fst customEdits -> Left (ConfigError (caseIdText caseId <> ".edits") "missing custom edit hook")
      _ -> Right ()
  pure (Campaign commands definitions)

-- | Portable definitions in author order.
campaignCases :: Campaign -> [CaseDefinition]
campaignCases (Campaign _ definitions) = map fst definitions

-- | Named reusable commands.
campaignCommands :: Campaign -> Map.Map CommandId Command
campaignCommands (Campaign commands _) = commands

-- | Observer notifications do not own verdicts.
data RunEvent = CaseStarted !CaseId | StageFinished !CaseId !Text !StageEvidence | CaseFinished !CaseResult
  deriving stock (Eq, Show)

-- | Explicit source/output roots and optional selected ledger. No mandatory output.
data RunOptions = RunOptions
  { sourceRoot :: !FilePath,
    outputDirectory :: !FilePath,
    sourcePolicy :: !SnapshotPolicy,
    selectedCases :: !(Maybe SelectedCases),
    progress :: !(RunEvent -> IO ()),
    workspaceCleanup :: !(Workspace -> IO ())
  }

-- | Fresh serial workspaces, whole working-tree inputs, all cases, silent observer.
defaultRunOptions :: FilePath -> FilePath -> RunOptions
defaultRunOptions source output = RunOptions source output defaultSnapshotPolicy Nothing (const (pure ())) (const (pure ()))

-- | Invalid configurations are separate from executed mutation results.
newtype ConfigurationFailure = ConfigurationFailure ConfigError
  deriving stock (Show)
  deriving anyclass (Exception)

-- | Execute selected cases. Runtime failures return structured results. On
-- asynchronous cancellation, finalize the partial report and rethrow the cause.
runCampaign :: RunOptions -> Campaign -> IO RunResult
runCampaign RunOptions {sourceRoot, outputDirectory, sourcePolicy, selectedCases, progress, workspaceCleanup} campaign@(Campaign commands definitions) = mask $ \restore -> do
  selected <- either (throwIO . ConfigurationFailure) pure $ maybe (mkSelectedCases [i | (CaseDefinition {caseId = i}, _) <- definitions]) Right selectedCases
  let ids = selectedCaseIds selected
  unless
    (all (`elem` [i | (CaseDefinition {caseId = i}, _) <- definitions]) ids)
    (throwIO (ConfigurationFailure (ConfigError "selection" "unknown case ID")))
  validateOutputLocation sourceRoot sourcePolicy outputDirectory `catch` \(e :: WorkspaceError) ->
    throwIO (ConfigurationFailure (ConfigError "output" (Text.pack (show e))))
  existing <- Dir.doesPathExist outputDirectory
  when existing (throwIO (ConfigurationFailure (ConfigError "output" "run directory already exists")))
  -- Executable availability is validated for selected commands only.
  let chosen = [(d, h) | i <- ids, (d@CaseDefinition {caseId = j}, h) <- definitions, i == j]
      commandIds = Set.fromList [c | (CaseDefinition {build, test}, _) <- chosen, c <- build : maybe [] pure test]
  forM_ (Set.toList commandIds) $ \key -> validateExecutable (commands Map.! key) >>= either (throwIO . ConfigurationFailure) pure
  resultsRef <- newIORef Map.empty
  failuresRef <- newIORef []
  contextRef <- newIORef (initialMetadata campaign chosen)
  sequenceRef <- newIORef 0
  baselineRef <- newIORef BaselineUnavailable
  mutationRef <- newIORef Unchanged
  stagesRef <- newIORef []
  errorsRef <- newIORef []
  cleanupRef <- newIORef []
  runIdentity <- newIORef ""
  producerIdentity <- newIORef Nothing
  let summary = do
        results <- Map.elems <$> readIORef resultsRef
        failures <- readIORef failuresRef
        either (throwIO . ConfigurationFailure) pure (summarizeRun selected results failures)
      stored = StoredReport <$> readIORef contextRef <*> summary
      journal event = do
        value <- stored
        sequence <- readIORef sequenceRef
        appendJournal outputDirectory sequence event value
        writeIORef sequenceRef (sequence + 1)
      currentEvidence stopped = CaseEvidence <$> readIORef baselineRef <*> readIORef mutationRef <*> readIORef stagesRef <*> readIORef errorsRef <*> readIORef cleanupRef <*> pure stopped
      cleanup workspace =
        workspaceCleanup workspace `catch` \(e :: SomeException) -> do
          modifyIORef' cleanupRef (++ [Text.pack (displayException e)])
          throwIO e
      updatePartial definition@CaseDefinition {caseId} = do
        observations <- currentEvidence (Just "case execution is incomplete")
        modifyIORef' resultsRef (Map.insert caseId (classifyCase definition observations))
      addCaseDetails caseId key value = modifyIORef' contextRef $ \context -> case context of
        Object metadata -> Object (mapToKeyMap metadata caseId key value)
        _ -> context
      runStage definition@CaseDefinition {caseId, expectation, evidenceMode} hooks role workspace stage command = do
        identity <- readIORef runIdentity
        attempt <-
          if stage `elem` [Test, Replay] && (evidenceMode == StructuredTestsV1 || isCrash expectation)
            then Just <$> Adapter.newEvidenceAttempt outputDirectory identity caseId stage role
            else pure Nothing
        let prefix = Text.unpack (caseIdText caseId <> "-" <> role <> "-" <> stageName stage)
            wanted = witnessesFor expectation stage
            effectiveCommand = withEnvironment (maybe [] Adapter.attemptEnvironment attempt) (withSelector definition command)
            options = case defaultProcessOptions outputDirectory prefix of
              ProcessOptions d p g _ _ observer -> ProcessOptions d p g wanted reservedEnvironment observer
            record processReport@ProcessReport {evidence, errors, logs, preservedWitnesses} = do
              normalized <- normalizeAttempt producerIdentity definition attempt evidence
              enhanced <- if evidenceMode == StructuredTestsV1 then observeStructured hooks normalized else enhance hooks normalized
              when (role == "candidate") $ do
                modifyIORef' stagesRef (++ [enhanced])
              let invalidEvidence = either pure (const []) (validateStageEvidence enhanced)
              modifyIORef' errorsRef (++ (errors ++ invalidEvidence))
              addCaseDetails
                caseId
                (role <> "-" <> stageName stage)
                ( object
                    [ "stage" .= stageJSON enhanced,
                      "logs" .= map logJSON logs,
                      "preservedWitnesses" .= preservedWitnesses,
                      "errors" .= errors,
                      "command" .= redactedCommand effectiveCommand,
                      "attempt" .= maybe Null Adapter.attemptIdentityJSON attempt
                    ]
                )
              updatePartial definition
              journal "stage"
              progress (StageFinished caseId role enhanced)
              pure (processReport, enhanced)
        process <- try (runCommand options workspace stage effectiveCommand)
        case process of
          Left ProcessAborted {report, cause} -> record report >> throwIO cause
          Right report -> record report
      runOne snapshot (definition@CaseDefinition {caseId, build, test, expectation}, hooks) = do
        writeIORef baselineRef BaselineUnavailable
        writeIORef mutationRef Unchanged
        writeIORef stagesRef []
        writeIORef errorsRef []
        writeIORef cleanupRef []
        writeIORef producerIdentity Nothing
        updatePartial definition
        attempted <- try $ restore $ do
          progress (CaseStarted caseId)
          baselinePassed <- withWorkspace snapshot $ \workspace ->
            ( do
                (buildReport, buildEvidence) <- runStage definition hooks "baseline" workspace Build (commands Map.! build)
                if not (stagePassed buildReport buildEvidence)
                  then pure False
                  else case test of
                    Nothing -> pure True
                    Just testId | needsTest expectation -> do
                      (testReport, testEvidence) <- runStage definition hooks "baseline" workspace Test (commands Map.! testId)
                      pure (stagePassed testReport testEvidence && baselineSelection definition testEvidence)
                    _ -> pure True
            )
              `withFinalizer` cleanup workspace
          writeIORef baselineRef (if baselinePassed then BaselinePassed else BaselineFailed "unchanged build/test or required selection failed")
          when baselinePassed $ do
            applied <- withEditedWorkspace (patchRunner caseId) hooks snapshot definition $ \workspace editEvidence ->
              ( do
                  writeIORef mutationRef (if expectation == Control then Unchanged else Changed)
                  addCaseDetails caseId "changes" (changesJSON editEvidence)
                  (buildReport, buildEvidence) <- runStage definition hooks "candidate" workspace Build (commands Map.! build)
                  when (stagePassed buildReport buildEvidence && needsTest expectation) $ forM_ test $ \testId -> do
                    (_, testEvidence) <- runStage definition hooks "candidate" workspace Test (commands Map.! testId)
                    case (expectation, testEvidence, hooks) of
                      (NamedTests expected RequireReplay, StageEvidence {outcome = Exited 1, replay = Just token, selection = SelectionEvidence {failedIds}}, CaseHooks {replayBuilder})
                        | expected == failedIds && validateStageEvidence testEvidence == Right () -> do
                            built <- maybe (pure (Right (Replay.replayCommand token (commands Map.! testId)))) (\builder -> builder token (commands Map.! testId)) replayBuilder
                            case built of
                              Left why -> addCaseDetails caseId "replayRejected" (String why)
                              Right replayCommand -> do
                                _ <- runStage definition hooks "candidate" workspace Replay replayCommand
                                pure ()
                      _ -> pure ()
              )
                `withFinalizer` cleanup workspace
            case applied of
              Left (InvalidEdit why) -> writeIORef mutationRef (EditRejected why)
              Left (EditInfrastructure why) -> modifyIORef' errorsRef (++ [why])
              Right () -> pure ()
        case attempted of
          Left (e :: SomeException) -> do
            modifyIORef' cleanupRef (++ finalizationErrors e)
            let original = originalException e
            case fromException original :: Maybe SomeAsyncException of
              Just _ -> do
                observations <- currentEvidence (Just "execution interrupted")
                modifyIORef' resultsRef (Map.insert caseId (classifyCase definition observations))
                throwIO original
              Nothing -> modifyIORef' errorsRef (++ [Text.pack (displayException e)])
          Right () -> pure ()
        observations <- currentEvidence Nothing
        let result = classifyCase definition observations
        modifyIORef' resultsRef (Map.insert caseId result)
        journal "case"
        progress (CaseFinished result)
      patchRunner caseId workspace args = do
        -- Patch check/apply share the exact supervisor used by build/test.
        let prefix = Text.unpack (caseIdText caseId <> if "--check" `elem` args then "-patch-check" else "-patch-apply")
            budget = either (error . show) id (mkStageBudget 5000000)
            command = Command "git" args Set.empty Nothing [] budget (OutputPolicy 65536)
        ProcessReport {evidence = patchEvidence@StageEvidence {outcome}, errors, logs} <- runCommand (defaultProcessOptions outputDirectory prefix) workspace Setup command `catch` \ProcessAborted {cause} -> throwIO cause
        addCaseDetails
          caseId
          (if "--check" `elem` args then "patch-check" else "patch-apply")
          (object ["stage" .= stageJSON patchEvidence, "logs" .= map logJSON logs, "errors" .= errors])
        journal "stage"
        unless (null errors) (throwIO (EditInfrastructure (Text.intercalate "; " errors)))
        case outcome of
          Exited 0 -> pure (Right ())
          Exited _ -> pure (Left "Git rejected textual patch; see patch logs")
          _ -> throwIO (EditInfrastructure ("Git patch supervisor failed: " <> Text.pack (show outcome)))
  attempted <- try $ restore $ do
    Dir.createDirectoryIfMissing True (takeDirectory outputDirectory)
    Dir.createDirectory outputDirectory
    identity <- Adapter.newRunIdentity outputDirectory
    writeIORef runIdentity identity
    modifyIORef' contextRef (\case Object o -> Object (KM.insert "runId" (String identity) o); other -> other)
    journal "selected"
    withSnapshot sourceRoot sourcePolicy $ \snapshot -> do
      modifyIORef' contextRef (addSnapshot snapshot)
      journal "snapshot"
      forM_ chosen (runOne snapshot)
  case attempted of
    Left (e :: SomeException) -> case fromException e :: Maybe SomeAsyncException of
      Just _ -> modifyIORef' failuresRef (++ [Interrupted (Text.pack (displayException e))])
      Nothing -> modifyIORef' failuresRef (++ [RunInfrastructure (Text.pack (displayException e))])
    Right () -> pure ()
  finalWrite <- try (journal "finalized" >> stored >>= writeReport outputDirectory) :: IO (Either SomeException ())
  case finalWrite of
    Left e -> modifyIORef' failuresRef (++ [RunInfrastructure ("report finalization failed: " <> Text.pack (displayException e))])
    Right () -> pure ()
  final <- summary
  case attempted of
    Left e | Just (_ :: SomeAsyncException) <- fromException e -> throwIO e
    _ -> case finalWrite of
      Left e | Just (_ :: SomeAsyncException) <- fromException e -> throwIO e
      _ -> pure final

stageName :: Stage -> Text
stageName s = case enumValue stageTable s of String t -> t; _ -> error "stage table"

needsTest :: Expectation -> Bool
needsTest BuildRejection {} = False
needsTest (Diagnostic Build _ _) = False
needsTest _ = True

witnessesFor :: Expectation -> Stage -> [Text]
witnessesFor (Diagnostic s _ witness) stage | s == stage = [witness]
witnessesFor (BuildRejection _ witness) Build = [witness]
witnessesFor _ _ = []

stagePassed :: ProcessReport -> StageEvidence -> Bool
stagePassed ProcessReport {errors} evidence@StageEvidence {outcome} = outcome == Exited 0 && null errors && validateStageEvidence evidence == Right ()

baselineSelection :: CaseDefinition -> StageEvidence -> Bool
baselineSelection CaseDefinition {expectation = NamedTests expected _} StageEvidence {selection = SelectionEvidence {selected, executed, executedIds, failedIds, skippedIds}} =
  maybe False (> 0) selected && maybe False (> 0) executed && expected `Set.isSubsetOf` executedIds && Set.null failedIds && Set.null (expected `Set.intersection` skippedIds)
baselineSelection CaseDefinition {evidenceMode = StructuredTestsV1} StageEvidence {selection = SelectionEvidence {selected, executed, failedIds}} = maybe False (> 0) selected && maybe False (> 0) executed && Set.null failedIds
baselineSelection _ _ = True

enhance :: CaseHooks -> StageEvidence -> IO StageEvidence
enhance CaseHooks {customEvidence = Nothing} evidence = pure evidence
enhance _ evidence@StageEvidence {outcome} | outcome `elem` [Timeout, Cancelled] = pure evidence
enhance CaseHooks {customEvidence = Just hook} evidence@(StageEvidence s o text unavailable _ _ duration logs) = do
  supplied <- hook evidence
  case supplied of
    Left why -> pure (StageEvidence s o text True (SelectionEvidence Nothing Nothing Nothing Set.empty Set.empty Set.empty [why]) Nothing duration logs)
    Right StageEvidence {selection, replay} -> pure (StageEvidence s o text unavailable selection replay duration logs)

isCrash :: Expectation -> Bool
isCrash CrashProbe {} = True
isCrash _ = False

reservedEnvironment :: [String]
reservedEnvironment = ["HENI_EVIDENCE_FILE", "HENI_RUN_ID", "HENI_CASE_ID", "HENI_STAGE", "HENI_ROLE", "HENI_ATTEMPT", "HENI_SELECTOR", "HENI_REPLAY_TOKEN", "HENI_REPLAY_GENERATOR"]

withEnvironment :: [(String, String)] -> Command -> Command
withEnvironment additions (Command exe args sensitive working env budget output) =
  Command exe args sensitive working (additions ++ filter (\(key, _) -> key `notElem` map fst additions) env) budget output

-- Protocol evidence is authoritative. A custom observer can reject it, but cannot
-- replace a framework's actual execution or replay membership.
observeStructured :: CaseHooks -> StageEvidence -> IO StageEvidence
observeStructured CaseHooks {customEvidence = Nothing} evidence = pure evidence
observeStructured _ evidence@StageEvidence {outcome} | outcome `elem` [Timeout, Cancelled] = pure evidence
observeStructured CaseHooks {customEvidence = Just hook} evidence@(StageEvidence s o text _ selection replay duration logs) =
  hook evidence >>= \case
    Right _ -> pure evidence
    Left why -> pure (StageEvidence s o text True (addSelectionError why selection) replay duration logs)

addSelectionError :: Text -> SelectionEvidence -> SelectionEvidence
addSelectionError why (SelectionEvidence d s e ids failed skipped errors) = SelectionEvidence d s e ids failed skipped (errors ++ [why])

normalizeAttempt :: IORef (Maybe Text) -> CaseDefinition -> Maybe Adapter.EvidenceAttempt -> StageEvidence -> IO StageEvidence
normalizeAttempt _ _ Nothing evidence = pure evidence
normalizeAttempt producerIdentity CaseDefinition {expectation, evidenceMode} (Just attempt@Adapter.EvidenceAttempt {outputRoot, role}) evidence@(StageEvidence s o text unavailable selection replay duration logs) = do
  let addArtifact relative = do
        exists <- Dir.doesFileExist (outputRoot ++ "/" ++ relative)
        pure [relative | exists]
  protocolArtifacts <- if evidenceMode == StructuredTestsV1 then addArtifact (Adapter.evidenceRelativePath attempt) else pure []
  probeArtifacts <- if isCrash expectation then addArtifact (Crash.probeRelativePath attempt) else pure []
  let artifacts = logs ++ protocolArtifacts ++ probeArtifacts
  if o `elem` [Timeout, Cancelled]
    then pure (StageEvidence s o text unavailable selection replay duration artifacts)
    else case expectation of
      CrashProbe _ probe -> do
        valid <- Crash.readCrashProbe attempt probe
        pure (StageEvidence s o (either (const "") (const probe) valid) unavailable selection replay duration artifacts)
      _
        | evidenceMode == StructuredTestsV1 ->
            Adapter.readEvidence attempt >>= \case
              Left why -> pure (StageEvidence s o text True (addSelectionError why unknownSelection) Nothing duration artifacts)
              Right (selected, replayed, producer) -> do
                expected <- readIORef producerIdentity
                if role == "baseline" then writeIORef producerIdentity (Just producer) else pure ()
                let normalized = if role /= "baseline" && expected /= Just producer then addSelectionError "reporter version changed after baseline" selected else selected
                pure (StageEvidence s o text unavailable normalized replayed duration artifacts)
      _ -> pure evidence

initialMetadata :: Campaign -> [(CaseDefinition, CaseHooks)] -> Value
initialMetadata (Campaign commands _) selected =
  object
    [ "platform" .= object ["os" .= Platform.os, "arch" .= Platform.arch, "compiler" .= Platform.compilerName, "compilerVersion" .= showVersion Platform.compilerVersion],
      "sourcePolicy" .= String "selected working-tree bytes including dirty/untracked regular files",
      "commands" .= object [Key.fromText (commandIdText key) .= redactedCommand command | (key, command) <- Map.toAscList commands],
      "definitions" .= map (caseJSON . fst) selected,
      "caseDetails" .= object [],
      "resources" .= ([] :: [Value])
    ]

redactedCommand :: Command -> Value
redactedCommand Command {executable, arguments, sensitiveArguments, workingDirectory, environment, budget, output} =
  object
    [ "executable" .= executable,
      "arguments" .= [if Set.member i sensitiveArguments then "<redacted>" else arg | (i, arg) <- zip [0 ..] arguments],
      "sensitiveArguments" .= Set.toAscList sensitiveArguments,
      "workingDirectory" .= fmap targetPath workingDirectory,
      "environmentOverrides" .= object [Key.fromString key .= String "<redacted>" | (key, _) <- environment],
      "environmentRedacted" .= True,
      "timeoutMicroseconds" .= budgetMicroseconds budget,
      "outputLimitBytes" .= case output of OutputPolicy {limitBytes} -> limitBytes
    ]

addSnapshot :: SourceSnapshot -> Value -> Value
addSnapshot snapshot (Object o) = Object (KM.insert "snapshot" (object ["identity" .= snapshotIdentity snapshot, "policy" .= policyJSON (snapshotPolicy snapshot)]) o)
addSnapshot _ other = other

policyJSON :: SnapshotPolicy -> Value
policyJSON SnapshotPolicy {includes, excludes} = object ["includes" .= map targetPath includes, "excludes" .= map targetPath excludes, "defaultExcludedNames" .= defaultExcludedNames, "defaultExcludedPrefixes" .= defaultExcludedPrefixes]

mapToKeyMap :: Object -> CaseId -> Text -> Value -> Object
mapToKeyMap metadata caseId key value = KM.insert "caseDetails" (Object updated) metadata
  where
    existing = case KM.lookup "caseDetails" metadata of Just (Object o) -> o; _ -> KM.empty
    caseKey = Key.fromText (caseIdText caseId)
    details = case KM.lookup caseKey existing of Just (Object o) -> o; _ -> KM.empty
    updated = KM.insert caseKey (Object (KM.insert (Key.fromText key) value details)) existing

logJSON :: LogArtifact -> Value
logJSON LogArtifact {stream, path, bytesSeen, bytesRetained, truncated} =
  object
    ["stream" .= (if stream == Stdout then String "stdout" else String "stderr"), "path" .= path, "bytesSeen" .= bytesSeen, "bytesRetained" .= bytesRetained, "truncated" .= truncated]

changesJSON :: EditEvidence -> Value
changesJSON (EditEvidence changes) = toJSON [object ["path" .= targetPath path, "before" .= nullable fileJSON before, "after" .= nullable fileJSON after] | FileChange {path, before, after} <- changes]
  where
    fileJSON FileEntry {bytes, executableBits} = object ["sha256" .= digest bytes, "executableBits" .= executableBits, "text" .= either (const Nothing) Just (Text.decodeUtf8' bytes), "byteLength" .= BS.length bytes]

withSelector :: CaseDefinition -> Command -> Command
withSelector CaseDefinition {selector} (Command executable arguments sensitive working environment budget output) =
  Command executable arguments sensitive working (maybe environment (\s -> ("HENI_SELECTOR", Text.unpack s) : filter ((/= "HENI_SELECTOR") . fst) environment) selector) budget output

originalException :: SomeException -> SomeException
originalException e = case fromException e of
  Just (WorkspaceFinalizationError (Just primary) _) -> originalException primary
  _ -> e

finalizationErrors :: SomeException -> [Text]
finalizationErrors e = case fromException e of
  Just (WorkspaceFinalizationError primary secondary) -> Text.pack (displayException secondary) : maybe [] finalizationErrors primary
  _ -> []
