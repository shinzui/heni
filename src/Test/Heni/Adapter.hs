-- | Attempt-bound framework-neutral JSON Lines evidence. Reporters describe
-- observations; only the core classifier chooses a verdict.
module Test.Heni.Adapter
  ( EvidenceAttempt (..),
    EvidenceError (..),
    TestObservation (..),
    SuiteEvidence (..),
    newRunIdentity,
    newEvidenceAttempt,
    evidencePath,
    evidenceRelativePath,
    attemptEnvironment,
    currentEvidenceAttempt,
    emitSuite,
    emitCurrentSuite,
    readEvidence,
    stableTestId,
    recordPropertyReplay,
    readPropertyReplay,
    attemptIdentityJSON,
    guardEvidenceAttempt,
  )
where

import Control.Exception
import Control.Monad (foldM, forM_, unless, when)
import Data.Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (Pair, Parser, parseEither)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory qualified as Dir
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO
import System.Posix.Temp (mkdtemp)
import Test.Heni.Case
import Test.Heni.Command
import Test.Heni.Expectation
import Test.Heni.Internal.Codec qualified as Codec
import Test.Heni.Internal.Files (WorkspaceError, checkedPath)
import Prelude hiding (sequence)

-- | Fresh identity allocated by the runner, never inferred from terminal text.
data EvidenceAttempt = EvidenceAttempt
  { outputRoot :: !FilePath,
    directoryName :: !FilePath,
    runId :: !Text,
    caseId :: !CaseId,
    stage :: !Stage,
    role :: !Text
  }
  deriving stock (Eq, Show)

-- | Protocol failures remain distinct from assertion failures.
newtype EvidenceError = EvidenceError Text
  deriving stock (Eq, Show)
  deriving anyclass (Exception)

-- | Complete per-test observations with stable full IDs.
data TestObservation = TestPassed !Text | TestFailed !Text | TestSkipped !Text | TestSetupFailed !Text !Text
  deriving stock (Eq, Show)

-- | Unknown unfiltered discovery is honest; selected/executed identities are exact.
data SuiteEvidence = SuiteEvidence
  { producerVersion :: !Text,
    discoveredIds :: !(Maybe [Text]),
    selectedIds :: ![Text],
    observations :: ![TestObservation],
    setupErrors :: ![Text],
    replayEvidence :: !(Maybe ReplayEvidence),
    counterexample :: ![Text]
  }
  deriving stock (Eq, Show)

-- | Campaign identity backed by an exclusively created private marker directory.
newRunIdentity :: FilePath -> IO Text
newRunIdentity output = do
  root <- Dir.makeAbsolute output
  Text.pack . takeFileName <$> mkdtemp (root </> ".identity-")

-- | Allocate a fresh destination for every baseline, candidate and replay attempt.
newEvidenceAttempt :: FilePath -> Text -> CaseId -> Stage -> Text -> IO EvidenceAttempt
newEvidenceAttempt output runId caseId stage role = do
  outputRoot <- Dir.makeAbsolute output
  directoryName <- takeFileName <$> mkdtemp (outputRoot </> ".attempt-")
  pure EvidenceAttempt {outputRoot, directoryName, runId, caseId, stage, role}

-- | Absolute destination supplied only to the child process.
evidencePath :: EvidenceAttempt -> FilePath
evidencePath a@EvidenceAttempt {outputRoot} = outputRoot </> evidenceRelativePath a

-- | Portable relative artifact reference.
evidenceRelativePath :: EvidenceAttempt -> FilePath
evidenceRelativePath EvidenceAttempt {directoryName} = directoryName </> "evidence.jsonl"

-- | Reserved environment entries, replaced freshly for each attempt.
attemptEnvironment :: EvidenceAttempt -> [(String, String)]
attemptEnvironment a@EvidenceAttempt {runId, caseId, stage, role, directoryName} =
  [ ("HENI_EVIDENCE_FILE", evidencePath a),
    ("HENI_RUN_ID", Text.unpack runId),
    ("HENI_CASE_ID", Text.unpack (caseIdText caseId)),
    ("HENI_STAGE", Text.unpack (stageText stage)),
    ("HENI_ROLE", Text.unpack role),
    ("HENI_ATTEMPT", directoryName)
  ]

-- | Normal direct framework execution has no destination. Partial Heni identity
-- configuration fails instead of emitting ambiguously attributed evidence.
currentEvidenceAttempt :: IO (Maybe EvidenceAttempt)
currentEvidenceAttempt =
  lookupEnv "HENI_EVIDENCE_FILE" >>= \case
    Nothing -> pure Nothing
    Just file -> do
      let required key = lookupEnv key >>= maybe (throwIO (EvidenceError ("missing " <> Text.pack key))) pure
      runId <- Text.pack <$> required "HENI_RUN_ID"
      caseId <- required "HENI_CASE_ID" >>= either (throwIO . EvidenceError . Text.pack . show) pure . mkCaseId . Text.pack
      stage <- required "HENI_STAGE" >>= either (throwIO . EvidenceError . Text.pack) pure . parseEither (Codec.enumParser Codec.stageTable) . String . Text.pack
      role <- Text.pack <$> required "HENI_ROLE"
      nonce <- required "HENI_ATTEMPT"
      unless (takeFileName file == "evidence.jsonl" && takeFileName (takeDirectory file) == nonce) (throwIO (EvidenceError "evidence destination/attempt mismatch"))
      pure (Just (EvidenceAttempt (takeDirectory (takeDirectory file)) nonce runId caseId stage role))

-- | Escape path separators and tildes so nested or parameterized names retain
-- unambiguous identity. Duplicate resulting IDs are rejected by the protocol.
stableTestId :: [Text] -> Text
stableTestId = Text.intercalate "/" . map (Text.replace "/" "~1" . Text.replace "~" "~0")

validateAttempt :: EvidenceAttempt -> IO ()
validateAttempt EvidenceAttempt {runId, role, directoryName} = do
  when (Text.null runId || role `notElem` ["baseline", "candidate"]) (throwIO (EvidenceError "invalid run identity or attempt role"))
  unless (takeFileName directoryName == directoryName) (throwIO (EvidenceError "invalid attempt directory name"))
  either (throwIO . EvidenceError . Text.pack . show) (const (pure ())) (mkRelativeTarget directoryName)

identityPairs :: EvidenceAttempt -> [Pair]
identityPairs EvidenceAttempt {runId, caseId, stage, role, directoryName} =
  ["protocolVersion" .= (1 :: Int), "runId" .= runId, "caseId" .= caseIdText caseId, "stage" .= String (stageText stage), "role" .= role, "attempt" .= directoryName]

stageText :: Stage -> Text
stageText stage = case Codec.enumValue Codec.stageTable stage of String t -> t; _ -> error "stage table"

-- | Shared identity object for other attempt-bound evidence channels.
attemptIdentityJSON :: EvidenceAttempt -> Value
attemptIdentityJSON = object . identityPairs

-- | Emit complete observed facts after framework completion. No completion is
-- written when execution is partial. Files must be fresh, and are capped at 8MiB.
emitSuite :: EvidenceAttempt -> SuiteEvidence -> IO ()
emitSuite attempt suite@SuiteEvidence {producerVersion, discoveredIds, selectedIds, observations, setupErrors, replayEvidence, counterexample} = do
  validateAttempt attempt
  either (throwIO . EvidenceError) pure (validateSuite suite)
  exists <- Dir.doesPathExist (evidencePath attempt)
  when exists (throwIO (EvidenceError "evidence destination already exists"))
  let begin = ("begin", ["producerVersion" .= producerVersion, "discoveredIds" .= discoveredIds, "selectedIds" .= selectedIds])
      testRecords = concatMap observationRecords observations
      setup = [("setup-error", ["message" .= why]) | why <- setupErrors]
      replayRecords = maybe [] (\r -> [("replay", ["replay" .= Codec.replayJSON r, "counterexample" .= counterexample])]) replayEvidence
      complete = ("complete", ["counts" .= countsJSON suite])
      records = [object (identityPairs attempt ++ ["sequence" .= n, "kind" .= String kind] ++ fields) | (n, (kind, fields)) <- zip [0 :: Int ..] (begin : testRecords ++ setup ++ replayRecords ++ [complete])]
      bytes = LBS.concat [encode record <> "\n" | record <- records]
  when (LBS.length bytes > 8388608) (throwIO (EvidenceError "test evidence exceeds 8MiB"))
  withBinaryFile (evidencePath attempt) WriteMode $ \file -> LBS.hPut file bytes >> hFlush file

-- | Reporter convenience: ordinary execution remains usable without Heni.
emitCurrentSuite :: SuiteEvidence -> IO ()
emitCurrentSuite suite = currentEvidenceAttempt >>= mapM_ (`emitSuite` suite)

observationId :: TestObservation -> Text
observationId = \case TestPassed t -> t; TestFailed t -> t; TestSkipped t -> t; TestSetupFailed t _ -> t

observationRecords :: TestObservation -> [(Text, [Pair])]
observationRecords observation = case observation of
  TestPassed t -> [("started", ["testId" .= t]), ("passed", ["testId" .= t])]
  TestFailed t -> [("started", ["testId" .= t]), ("failed", ["testId" .= t])]
  TestSkipped t -> [("skipped", ["testId" .= t])]
  TestSetupFailed t why -> [("setup-failed", ["testId" .= t, "message" .= why])]

validateSuite :: SuiteEvidence -> Either Text ()
validateSuite SuiteEvidence {producerVersion, discoveredIds, selectedIds, observations, replayEvidence} = do
  when (Text.null producerVersion) (Left "missing reporter version identity")
  unless (unique selectedIds && all (not . Text.null) selectedIds) (Left "empty or duplicate selected test identity")
  forM_ discoveredIds $ \ids -> unless (unique ids && all (not . Text.null) ids && Set.fromList selectedIds `Set.isSubsetOf` Set.fromList ids) (Left "selected identities do not agree with discovery")
  let observed = map observationId observations
      failed = Set.fromList [t | TestFailed t <- observations]
  unless (unique observed && Set.fromList selectedIds == Set.fromList observed) (Left "incomplete or conflicting selected test observations")
  forM_ replayEvidence $ \ReplayEvidence {token, generator, failures} ->
    unless (not (Text.null token || Text.null generator) && Text.length token <= 65536 && Text.length generator <= 65536 && failures `Set.isSubsetOf` failed && not (Set.null failures)) (Left "replay does not identify the observed failures")
  where
    unique xs = Set.size (Set.fromList xs) == length xs

countsJSON :: SuiteEvidence -> Value
countsJSON SuiteEvidence {discoveredIds, selectedIds, observations, setupErrors} =
  object
    [ "discovered" .= fmap length discoveredIds,
      "selected" .= length selectedIds,
      "executed" .= length [() | o <- observations, case o of TestPassed {} -> True; TestFailed {} -> True; _ -> False],
      "passed" .= length [() | TestPassed {} <- observations],
      "failed" .= length [() | TestFailed {} <- observations],
      "skipped" .= length [() | TestSkipped {} <- observations],
      "setupErrors" .= (length setupErrors + length [() | TestSetupFailed {} <- observations])
    ]

data Record
  = Begin !Text !(Maybe [Text]) ![Text]
  | Started !Text
  | Finished !TestObservation
  | SetupError !Text
  | ReplayRecord !ReplayEvidence ![Text]
  | Complete !Value
  deriving stock (Show)

parseRecord :: EvidenceAttempt -> Int -> Value -> Parser Record
parseRecord expected index value =
  withObject
    "test-evidence record"
    ( \o -> do
        kind <- o .: "kind" :: Parser Text
        let fields = case kind of "begin" -> ["producerVersion", "discoveredIds", "selectedIds"]; "setup-error" -> ["message"]; "invalidated" -> ["message"]; "replay" -> ["replay", "counterexample"]; "complete" -> ["counts"]; "setup-failed" -> ["testId", "message"]; _ -> ["testId"]
        Codec.strictObject
          "test-evidence record"
          (["protocolVersion", "runId", "caseId", "stage", "role", "attempt", "sequence", "kind"] ++ fields)
          ( \record -> do
              version <- record .: "protocolVersion"
              unless (version == (1 :: Int)) (fail "unsupported evidence protocol version")
              forM_ (identityPairs expected) $ \(key, wanted) -> unless (KM.lookup key record == Just wanted) (fail "stale or wrong run/case/stage/attempt identity")
              when (kind == "invalidated") $ do
                why <- record .: "message"
                fail ("reporter invalidated attempt: " ++ why)
              sequence <- record .: "sequence"
              unless (sequence == index) (fail "evidence event sequence gap or duplicate")
              case kind of
                "begin" -> Begin <$> record .: "producerVersion" <*> record .: "discoveredIds" <*> record .: "selectedIds"
                "started" -> Started <$> record .: "testId"
                "passed" -> Finished . TestPassed <$> record .: "testId"
                "failed" -> Finished . TestFailed <$> record .: "testId"
                "skipped" -> Finished . TestSkipped <$> record .: "testId"
                "setup-failed" -> Finished <$> (TestSetupFailed <$> record .: "testId" <*> record .: "message")
                "setup-error" -> SetupError <$> record .: "message"
                "replay" -> ReplayRecord <$> (record .: "replay" >>= Codec.parseReplay) <*> record .: "counterexample"
                "complete" -> Complete <$> record .: "counts"
                _ -> fail "unknown evidence event kind"
          )
          value
    )
    value

-- | Read only the fresh attempt's bounded file and verify every identity,
-- sequence, execution transition, completion count and failure membership.
readEvidence :: EvidenceAttempt -> IO (Either Text (SelectionEvidence, Maybe ReplayEvidence, Text))
readEvidence attempt = evidenceIO $ do
  validateAttempt attempt
  bytes <- readAttemptFile attempt "evidence.jsonl"
  unless (not (BS.null bytes) && BS.last bytes == 10) (throwIO (EvidenceError "incomplete evidence: missing final newline/completion"))
  let lines' = init (BS.split 10 bytes)
  values <- either (throwIO . EvidenceError . Text.pack) pure (mapM Codec.decodeJSON lines')
  records <- either (throwIO . EvidenceError . Text.pack) pure (mapM (\(index, value) -> parseEither (parseRecord attempt index) value) (zip [0 ..] values))
  suite <- either (throwIO . EvidenceError) pure (normalize records)
  let SuiteEvidence {producerVersion, discoveredIds, selectedIds, observations, setupErrors, replayEvidence} = suite
      executedIds = Set.fromList [t | o <- observations, t <- case o of TestPassed t -> [t]; TestFailed t -> [t]; _ -> []]
      failedIds = Set.fromList [t | TestFailed t <- observations]
      skippedIds = Set.fromList [t | TestSkipped t <- observations]
      errors = setupErrors ++ [t <> ": " <> why | TestSetupFailed t why <- observations]
  pure (SelectionEvidence (fmap length discoveredIds) (Just (length selectedIds)) (Just (Set.size executedIds)) executedIds failedIds skippedIds errors, replayEvidence, producerVersion)

normalize :: [Record] -> Either Text SuiteEvidence
normalize records = case records of
  Begin producer discovered selected : rest -> case reverse rest of
    Complete counts : reversed -> do
      (_, finished, errors, replay, counterexample) <- foldM (step (Set.fromList selected)) (Set.empty, Map.empty, [], Nothing, []) (reverse reversed)
      let suite = SuiteEvidence producer discovered selected (Map.elems finished) errors replay counterexample
      validateSuite suite
      unless (counts == countsJSON suite) (Left "completion counts contradict observed identities")
      pure suite
    _ -> Left "missing final completion record"
  _ -> Left "missing initial evidence identity/selection record"
  where
    step selected (started, finished, errors, replay, counterexample) record = case record of
      Started t -> do
        unless (t `Set.member` selected && t `Set.notMember` started && Map.notMember t finished) (Left "unexpected or repeated test start")
        pure (Set.insert t started, finished, errors, replay, counterexample)
      Finished observation -> do
        let t = observationId observation
            needsStart = case observation of TestPassed {} -> True; TestFailed {} -> True; _ -> False
        unless (t `Set.member` selected && Map.notMember t finished && (t `Set.member` started) == needsStart) (Left "conflicting test completion/start identity")
        pure (started, Map.insert t observation finished, errors, replay, counterexample)
      SetupError why -> pure (started, finished, errors ++ [why], replay, counterexample)
      ReplayRecord value examples -> case replay of
        Just _ -> Left "duplicate replay evidence"
        Nothing -> pure (started, finished, errors, Just value, examples)
      _ -> Left "duplicate or misplaced begin/completion record"

readAttemptFile :: EvidenceAttempt -> FilePath -> IO BS.ByteString
readAttemptFile EvidenceAttempt {outputRoot, directoryName} name = do
  target <- either (throwIO . EvidenceError . Text.pack . show) pure (mkRelativeTarget (directoryName </> name))
  path <- checkedPath outputRoot target
  bytes <- withBinaryFile path ReadMode (\file -> BS.hGet file 8388609)
  when (BS.length bytes > 8388608) (throwIO (EvidenceError "test evidence exceeds 8MiB"))
  pure bytes

-- | Optional framework property helpers record the exact seed/size token and
-- generator contract in a separate fresh sidecar, later included in protocol.
recordPropertyReplay :: ReplayEvidence -> [Text] -> IO ()
recordPropertyReplay replay counterexample =
  currentEvidenceAttempt
    >>= mapM_
      ( \attempt@EvidenceAttempt {outputRoot, directoryName} -> do
          let path = outputRoot </> directoryName </> "property.json"
          exists <- Dir.doesPathExist path
          when exists (throwIO (EvidenceError "one QuickCheck replay property per attempt is supported"))
          LBS.writeFile path (encode (object (identityPairs attempt ++ ["replay" .= Codec.replayJSON replay, "counterexample" .= counterexample])))
      )

-- | Validate a helper sidecar before a reporter incorporates it into completion.
readPropertyReplay :: EvidenceAttempt -> IO (Maybe (ReplayEvidence, [Text]))
readPropertyReplay attempt@EvidenceAttempt {outputRoot, directoryName} = do
  exists <- Dir.doesPathExist (outputRoot </> directoryName </> "property.json")
  if not exists
    then pure Nothing
    else do
      bytes <- readAttemptFile attempt "property.json"
      value <- either (throwIO . EvidenceError . Text.pack) pure (Codec.decodeJSON bytes)
      either
        (throwIO . EvidenceError . Text.pack)
        (pure . Just)
        ( parseEither
            ( Codec.strictObject "property replay" ["protocolVersion", "runId", "caseId", "stage", "role", "attempt", "replay", "counterexample"] $ \o -> do
                forM_ (identityPairs attempt) $ \(key, wanted) -> unless (KM.lookup key o == Just wanted) (fail "stale property replay identity")
                (,) <$> (o .: "replay" >>= Codec.parseReplay) <*> o .: "counterexample"
            )
            value
        )

evidenceIO :: IO a -> IO (Either Text a)
evidenceIO action =
  catches
    (Right <$> action)
    [ Handler (\(EvidenceError why) -> pure (Left why)),
      Handler (\(e :: IOException) -> pure (Left (Text.pack (show e)))),
      Handler (\(e :: WorkspaceError) -> pure (Left (Text.pack (show e))))
    ]

-- | An exception after a framework wrote completion must invalidate that proof,
-- while retaining the prior artifact. Ordinary framework success/failure exits
-- are preserved. The runner still owns timeout and cancellation.
guardEvidenceAttempt :: EvidenceAttempt -> IO a -> IO a
guardEvidenceAttempt attempt action =
  action `catch` \(e :: SomeException) -> do
    case fromException e :: Maybe ExitCode of
      Just ExitSuccess -> pure ()
      Just (ExitFailure 1) -> pure ()
      _ -> do
        let line = encode (object (identityPairs attempt ++ ["sequence" .= (-1 :: Int), "kind" .= String "invalidated", "message" .= displayException e])) <> "\n"
        _ <- try (LBS.appendFile (evidencePath attempt) line) :: IO (Either IOException ())
        pure ()
    throwIO e
