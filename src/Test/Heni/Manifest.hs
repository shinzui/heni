-- | Strict version-one portable manifests and isolated applicability checks.
module Test.Heni.Manifest
  ( Manifest,
    decodeManifest,
    readManifest,
    manifestSourceRoot,
    manifestPolicy,
    manifestCampaign,
    manifestRunOptions,
    caseDefinitionJSON,
    Applicability (..),
    checkManifest,
  )
where

import Control.Exception
import Control.Monad (forM, forM_, unless, when)
import Data.Aeson
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (JSONPathElement (..), Parser, parseEither)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory qualified as Dir
import System.FilePath (isAbsolute, takeDirectory, (</>))
import Test.Heni.Case
import Test.Heni.Command
import Test.Heni.Edit
import Test.Heni.Expectation
import Test.Heni.Internal.Codec
import Test.Heni.Internal.Files (withOwnedDirectory)
import Test.Heni.Process
import Test.Heni.Resource qualified as Resource
import Test.Heni.Runner
import Test.Heni.Workspace

-- | Source roots are relative to the manifest file until readManifest resolves them.
data Manifest = Manifest !FilePath !SnapshotPolicy !Campaign !Execution

data Execution = Execution ![Resource.ResourceProvider] !(Map.Map CaseId [Text]) !Int !ReusePolicy

-- | Declared source root, resolved by readManifest.
manifestSourceRoot :: Manifest -> FilePath
manifestSourceRoot (Manifest root _ _ _) = root

-- | Explicit source inclusion and exclusion choices.
manifestPolicy :: Manifest -> SnapshotPolicy
manifestPolicy (Manifest _ policy _ _) = policy

-- | The same validated campaign used by Haskell callers.
manifestCampaign :: Manifest -> Campaign
manifestCampaign (Manifest _ _ campaign _) = campaign

-- | Lower portable execution/resource options into the shared library runner.
manifestRunOptions :: FilePath -> Manifest -> RunOptions
manifestRunOptions output (Manifest root policy _ (Execution providers claims jobs reuse)) =
  (defaultRunOptions root output) {sourcePolicy = policy, workers = jobs, resources = providers, resourceClaims = claims, reusePolicy = reuse}

-- | Explicit portable case representation, shared with report metadata.
caseDefinitionJSON :: CaseDefinition -> Value
caseDefinitionJSON = caseJSON

-- | Decode at most 4MiB, reject duplicates/unknown keys and validate all references.
decodeManifest :: BS.ByteString -> Either ConfigError Manifest
decodeManifest bytes
  | BS.length bytes > 4194304 = Left (ConfigError "manifest" "manifest exceeds 4MiB")
  | otherwise = either (Left . ConfigError "manifest" . Text.pack) Right $ decodeJSON bytes >>= parseEither parseManifest

parseManifest :: Value -> Parser Manifest
parseManifest = strictObject "manifest" ["schemaVersion", "sourceRoot", "sourcePolicy", "commands", "cases", "resources", "execution"] $ \o -> do
  version <- o .: "schemaVersion"
  unless (version == (1 :: Int)) (fail "unsupported schemaVersion")
  root <- defaultField o "sourceRoot" "."
  when (null root || isAbsolute root || '\0' `elem` root) (fail "sourceRoot must be a nonempty relative path")
  policy <- case KM.lookup "sourcePolicy" o of Nothing -> pure defaultSnapshotPolicy; Just value -> parsePolicy value
  commandValues <- o .: "commands" :: Parser Object
  commands <- forM (KM.toList commandValues) $ \(key, value) -> do
    ident <- checked (mkCommandId (Key.toText key))
    command <- parsePortableCommand value <?> Key key
    pure (ident, command)
  caseValues <- o .: "cases"
  definitions <- forM (zip [0 ..] caseValues) $ \(index, value) -> parsePortableCase value <?> Index index
  campaign <- checked (mkCampaign (Map.fromList commands) [(definition, noHooks) | definition <- definitions])
  providers <- defaultField o "resources" [] >>= mapM (parseResource (Map.fromList commands))
  checked (Resource.validateResources providers)
  claims <- forM (zip definitions caseValues) $ \(CaseDefinition {caseId}, value) ->
    withObject
      "case resource claims"
      ( \c -> do
          names <- defaultField c "resources" []
          unless (length names == Set.size (Set.fromList names) && all (`elem` map Resource.resourceName providers) names) (fail "unknown or duplicate resource claim")
          pure (caseId, names)
      )
      value
  (jobs, reuse) <- case KM.lookup "execution" o of Nothing -> pure (1, Fresh); Just value -> parseExecution value
  pure (Manifest root policy campaign (Execution providers (Map.fromList claims) jobs reuse))

parsePolicy :: Value -> Parser SnapshotPolicy
parsePolicy = strictObject "sourcePolicy" ["includes", "excludes"] $ \o ->
  SnapshotPolicy <$> (defaultField o "includes" [] >>= mapM (checked . mkRelativeTarget)) <*> (defaultField o "excludes" [] >>= mapM (checked . mkRelativeTarget))

defaultField :: (FromJSON a) => Object -> Key -> a -> Parser a
defaultField o key fallback = maybe (pure fallback) parseJSON (KM.lookup key o)

parsePortableCommand :: Value -> Parser Command
parsePortableCommand = strictObject "command" ["executable", "arguments", "sensitiveArguments", "workingDirectory", "environment", "timeoutSeconds", "outputLimitBytes"] $ \o -> do
  executable <- o .: "executable"
  arguments <- defaultField o "arguments" []
  sensitive <- defaultField o "sensitiveArguments" [] >>= uniqueSet
  working <- o .:? "workingDirectory" >>= traverse (checked . mkRelativeTarget)
  environmentValues <- defaultField o "environment" KM.empty
  environment <- forM (KM.toList environmentValues) $ \(key, value) -> (,) (Key.toString key) <$> parseJSON value
  seconds <- defaultField o "timeoutSeconds" (30 :: Double)
  unless (seconds > 0 && seconds <= 86400 && not (isNaN seconds || isInfinite seconds)) (fail "timeoutSeconds must be positive and finite, at most 86400")
  budget <- checked (mkStageBudget (ceiling (seconds * 1000000)))
  output <- OutputPolicy <$> defaultField o "outputLimitBytes" 1048576
  let command = Command executable arguments sensitive working environment budget output
  checked (validateCommand command)
  pure command

parsePortableCase :: Value -> Parser CaseDefinition
parsePortableCase value = do
  -- Defaults never turn an explicit null into a missing non-nullable field.
  withObject
    "case"
    ( \o -> do
        forM_ ["tags", "edits"] $ \key -> when (KM.lookup key o == Just Null) (fail (Key.toString key ++ " cannot be null"))
        edits <- o .:? "edits" .!= []
        forM_ edits $ withObject "edit" $ \edit -> when (KM.lookup "occurrences" edit == Just Null) (fail "occurrences cannot be null")
    )
    value
  withObject
    "case"
    ( \o -> case KM.lookup "expect" o of
        Just (Object expected) | KM.lookup "replayRequired" expected == Just Null -> fail "replayRequired cannot be null"
        _ -> pure ()
    )
    value
  stripped <- withObject "case" (pure . Object . KM.delete "resources") value
  definition@CaseDefinition {edits, expectation, evidenceMode} <- parseCase stripped
  forM_ edits $ \case CustomEdit {} -> fail "custom Haskell hooks cannot be serialized in manifests"; _ -> pure ()
  case expectation of
    NamedTests {} | evidenceMode /= StructuredTestsV1 -> fail "named-tests requires adapter: heni-v1"
    NamedTests {} -> pure definition
    CrashProbe {} -> pure definition
    _ -> pure definition

-- | Read with source paths anchored to the manifest location, not the caller's cwd.
readManifest :: FilePath -> IO (Either ConfigError Manifest)
readManifest path = do
  result <- try $ do
    absolute <- Dir.makeAbsolute path
    bytes <- BS.readFile absolute
    case decodeManifest bytes of
      Left e -> pure (Left e)
      Right (Manifest root policy campaign execution) -> do
        source <- Dir.canonicalizePath (takeDirectory absolute </> root)
        pure (Right (Manifest source policy campaign execution))
  pure $ either (Left . ConfigError "manifest" . Text.pack . show) id (result :: Either IOException (Either ConfigError Manifest))

-- | Static validation plus checked edit applicability; no test discovery or baseline.
data Applicability = Applicability {caseId :: !CaseId, applicable :: !Bool, diagnostics :: ![Text]}
  deriving stock (Eq, Show)

-- | Check available commands and edits in fresh disposable candidates. Git is
-- optional unless a selected definition contains a patch, and uses runCommand.
checkManifest :: Manifest -> IO (Either ConfigError [Applicability])
checkManifest (Manifest root policy campaign _) =
  catches
    (Right <$> action)
    [ Handler (\(e :: IOException) -> pure (Left (ConfigError "check" (Text.pack (show e))))),
      Handler (\(e :: WorkspaceError) -> pure (Left (ConfigError "source" (Text.pack (show e)))))
    ]
  where
    action = do
      availability <- mapM validateExecutable (Map.elems (campaignCommands campaign))
      let commandErrors = [Text.pack (show e) | Left e <- availability]
      withOwnedDirectory ".heni-check-" $ \logs -> withSnapshot root policy $ \snapshot ->
        forM (campaignCases campaign) $ \definition@CaseDefinition {caseId} -> do
          result <- withEditedWorkspace (gitRunner logs caseId) noHooks snapshot definition (\_ _ -> pure ())
          let editErrors = either (pure . Text.pack . show) (const []) result
              diagnostics = commandErrors ++ editErrors
          pure (Applicability caseId (null diagnostics) diagnostics)
    gitRunner logs caseId workspace args = do
      let prefix = Text.unpack (caseIdText caseId) ++ if "--check" `elem` args then "-check" else "-apply"
          budget = either (error . show) id (mkStageBudget 5000000)
          command = Command "git" args Set.empty Nothing [] budget (OutputPolicy 65536)
      ProcessReport {evidence = StageEvidence {outcome}, errors} <- runCommand (defaultProcessOptions logs prefix) workspace Setup command `catch` \ProcessAborted {cause} -> throwIO cause
      unless (null errors) (throwIO (EditInfrastructure (Text.intercalate "; " errors)))
      case outcome of
        Exited 0 -> pure (Right ())
        Exited _ -> pure (Left "Git rejected patch applicability")
        _ -> throwIO (EditInfrastructure (Text.pack (show outcome)))

parseExecution :: Value -> Parser (Int, ReusePolicy)
parseExecution = strictObject "execution" ["workers", "baselineReuse"] $ \o -> do
  jobs <- defaultField o "workers" 1
  unless (jobs > 0 && jobs <= 256) (fail "workers must be between 1 and 256")
  reuse <- case KM.lookup "baselineReuse" o of
    Nothing -> pure Fresh
    Just Null -> pure Fresh
    Just value ->
      strictObject
        "baselineReuse"
        ["toolchain", "adapter"]
        ( \r -> do
            toolchain <- r .: "toolchain"
            adapter <- r .:? "adapter"
            unless (not (Text.null (Text.strip toolchain)) && maybe True (not . Text.null . Text.strip) adapter) (fail "empty reuse identity")
            pure (ReuseBaselines toolchain adapter)
        )
        value
  pure (jobs, reuse)

parseResource :: Map.Map CommandId Command -> Value -> Parser Resource.ResourceProvider
parseResource commands = strictObject "resource" ["name", "scope", "capacity", "identity", "version", "epoch", "environment", "setup", "reset", "teardown"] $ \o -> do
  name <- o .: "name"
  scope <-
    defaultField o "scope" ("case" :: Text) >>= \case
      "campaign" -> pure Resource.CampaignScope
      "worker" -> pure Resource.WorkerScope
      "case" -> pure Resource.CaseScope
      _ -> fail "unknown resource scope"
  capacity <- defaultField o "capacity" 1
  identity <- o .: "identity"
  version <- o .: "version"
  epoch <- o .:? "epoch"
  env <- defaultField o "environment" KM.empty >>= mapM (\(key, value) -> (Key.toString key,) <$> parseJSON value) . KM.toList
  let binding = Resource.ResourceBinding identity version epoch env
  _ <- checked (Resource.bindingEnvironment [(name, binding)])
  let referenced key = do
        ident <- o .: key >>= checked . mkCommandId
        maybe (fail ("unknown resource command: " ++ Key.toString key)) pure (Map.lookup ident commands)
  Resource.commandResource name scope capacity binding <$> referenced "setup" <*> referenced "reset" <*> referenced "teardown"
