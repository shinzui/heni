-- | Versioned portable reports and read-only journal recovery.
module Test.Heni.Report
  ( StoredReport (..),
    ReportError (..),
    reportJSON,
    readReport,
    recoverReport,
    writeReport,
    appendJournal,
    runResultJSON,
  )
where

import Control.Exception
import Control.Monad (forM_, unless)
import Data.Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (Parser, parseEither)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory qualified as Dir
import System.FilePath (takeDirectory, (</>))
import System.IO
import Test.Heni.Case (mkRelativeTarget, mkSelectedCases)
import Test.Heni.Expectation (StageEvidence (..))
import Test.Heni.Internal.Codec
import Test.Heni.Internal.Files (WorkspaceError, checkedPath)
import Test.Heni.Result
import Prelude hiding (sequence)

-- | Version-one run-result payload used by nonterminal renderers.
runResultJSON :: RunResult -> Value
runResultJSON = resultJSON

-- | Effective, redacted configuration and the authoritative classified result.
data StoredReport = StoredReport {metadata :: !Value, result :: !RunResult}
  deriving stock (Eq, Show)

-- | IO, schema, ledger, journal and evidence-containment failures.
newtype ReportError = ReportError Text
  deriving stock (Eq, Show)
  deriving anyclass (Exception)

-- | Stable v1 envelope, with codecs independent of Haskell constructor names.
reportJSON :: StoredReport -> Value
reportJSON StoredReport {metadata, result} =
  object
    ["schemaVersion" .= (1 :: Int), "toolVersion" .= String "0.1.0.0", "metadata" .= metadata, "result" .= resultJSON result]

parseReport :: Value -> Parser StoredReport
parseReport = strictObject "report" ["schemaVersion", "toolVersion", "metadata", "result"] $ \o -> do
  version <- o .: "schemaVersion"
  unless (version == (1 :: Int)) (fail "unsupported report schemaVersion")
  (_ :: Text) <- o .: "toolVersion"
  StoredReport <$> o .: "metadata" <*> (o .: "result" >>= parseResult)

-- | Atomic replacement within an exclusively allocated run directory. This
-- protects readers from half-written JSON, not from arbitrary storage failure.
writeReport :: FilePath -> StoredReport -> IO ()
writeReport directory stored = mask $ \restore -> do
  (temporary, file) <- openBinaryTempFile directory ".report-"
  let remove = do
        _ <- try (hClose file) :: IO (Either IOException ())
        exists <- Dir.doesFileExist temporary
        if exists then Dir.removeFile temporary else pure ()
  (restore (LBS.hPut file (encode (reportJSON stored))) >> hClose file >> Dir.renameFile temporary (directory </> "report.json")) `onException` remove

-- | Append a complete ledger snapshot after each observation. Sequence numbers
-- make missing, duplicate and reordered records detectable during recovery.
appendJournal :: FilePath -> Int -> Text -> StoredReport -> IO ()
appendJournal directory sequence event stored =
  withBinaryFile (directory </> "journal.jsonl") AppendMode $ \file -> do
    LBS.hPut file (encode (object ["sequence" .= sequence, "event" .= event, "report" .= reportJSON stored]))
    BS.hPut file "\n"
    hFlush file

-- | Read and validate summary accounting and every referenced log's containment
-- and existence. Nothing executes while reading evidence.
readReport :: FilePath -> IO (Either ReportError StoredReport)
readReport path = handleErrors $ do
  bytes <- BS.readFile path
  value <- either (throwIO . ReportError . Text.pack) pure (decodeJSON bytes)
  stored <- either (throwIO . ReportError . Text.pack) pure (parseEither parseReport value)
  validateArtifacts (takeDirectory path) stored
  pure stored

validateArtifacts :: FilePath -> StoredReport -> IO ()
validateArtifacts root StoredReport {metadata, result = RunResult {results}} = do
  let caseStages = concat [stages | CaseResult {evidence = CaseEvidence {stages}} <- results]
      metadataStages = case metadata of
        Object o -> case KM.lookup "caseDetails" o of
          Just (Object cases) -> [value | Object details <- KM.elems cases, Object observation <- KM.elems details, Just value <- [KM.lookup "stage" observation]]
          _ -> []
        _ -> []
  additionalStages <- mapM (either (throwIO . ReportError . Text.pack) pure . parseEither parseStage) metadataStages
  forM_ (caseStages ++ additionalStages) $ \StageEvidence {logPaths} -> forM_ logPaths $ \relative -> do
    target <- either (throwIO . ReportError . Text.pack . show) pure (mkRelativeTarget relative)
    path <- checkedPath root target
    exists <- Dir.doesFileExist path
    unless exists (throwIO (ReportError ("missing evidence artifact: " <> Text.pack relative)))

-- | Recover the last complete journal snapshot, ignoring only a truncated final
-- non-newline record. Interior corruption, sequence gaps and changed ledgers
-- are errors. The recovered run is explicitly untrustworthy and never resumed.
recoverReport :: FilePath -> IO (Either ReportError StoredReport)
recoverReport directory = handleErrors $ do
  bytes <- BS.readFile (directory </> "journal.jsonl")
  let lines' = BS.split 10 bytes
      complete = if BS.null bytes || BS.last bytes == 10 then init lines' else lines'
  records <- mapM decodeRecord (zip [0 :: Int ..] complete)
  usable <- case reverse records of
    [] -> throwIO (ReportError "empty journal")
    Right stored : _ -> pure stored
    Left why : rest | not (BS.null bytes) && BS.last bytes /= 10 && "end-of-input" `Text.isInfixOf` why -> case rest of
      Right stored : _ -> pure stored
      _ -> throwIO (ReportError "no complete journal record")
    Left why : _ -> throwIO (ReportError why)
  let interior = if not (BS.null bytes) && BS.last bytes /= 10 then init records else records
  forM_ interior (either (throwIO . ReportError) (const (pure ())))
  let ledgers = [ids | Right StoredReport {result = RunResult {selectedIds = ids}} <- records]
  case ledgers of
    first : rest -> unless (all (== first) rest) (throwIO (ReportError "journal selected ledger changed"))
    [] -> throwIO (ReportError "journal has no ledger")
  let StoredReport metadata RunResult {selectedIds, results, failures} = usable
  selected <- either (throwIO . ReportError . Text.pack . show) pure (mkSelectedCases selectedIds)
  recovered <- either (throwIO . ReportError . Text.pack . show) pure (summarizeRun selected results (failures ++ [RunInfrastructure "recovered journal; execution was not resumed"]))
  let stored = StoredReport metadata recovered
  validateArtifacts directory stored
  pure stored
  where
    decodeRecord (expected, line) = case decodeJSON line of
      Left why -> pure (Left (Text.pack why))
      Right value -> do
        record <-
          either
            (throwIO . ReportError . Text.pack)
            pure
            ( parseEither
                ( strictObject "journal record" ["sequence", "event", "report"] $ \o -> do
                    sequence <- o .: "sequence"
                    unless (sequence == expected) (fail "journal sequence gap or duplicate")
                    event <- o .: "event"
                    unless ((event :: Text) `elem` ["selected", "snapshot", "stage", "case", "finalized"]) (fail "unknown journal event")
                    o .: "report" >>= parseReport
                )
                value
            )
        pure (Right record)

handleErrors :: forall a. IO a -> IO (Either ReportError a)
handleErrors action =
  catches
    (Right <$> action)
    [ Handler (pure . Left :: ReportError -> IO (Either ReportError a)),
      Handler (\(e :: WorkspaceError) -> pure (Left (ReportError (Text.pack (show e))))),
      Handler (\(e :: IOException) -> pure (Left (ReportError (Text.pack (show e)))))
    ]
