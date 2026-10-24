-- | Command application: parsing and presentation only; the library owns behavior.
module Heni.Cli (mainCli, selectDefinitions, exitCodeFor) where

import Control.Exception
import Control.Monad (forM_, unless)
import Data.Aeson hiding (Options)
import Data.ByteString.Lazy.Char8 qualified as LBS
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Version (showVersion)
import Paths_heni_cli (version)
import System.Environment (getArgs)
import System.Exit
import System.FilePath ((</>))
import System.IO
import Test.Heni
import Text.Read (readMaybe)

data Options = Options !Bool !String ![Text] ![Text] !(Maybe FilePath) !Int !Bool

defaults :: Options
defaults = Options False "auto" [] [] Nothing 1 False

mainCli :: IO ()
mainCli = do
  args <- getArgs
  case args of
    ["--version"] -> putStrLn ("heni " ++ showVersion version)
    [] -> putStrLn help >> exitWith (ExitFailure 2)
    _ | "--help" `elem` args -> putStrLn help
    command : path : rest | command `elem` ["check", "list", "run", "report"] -> case parseOptions command defaults rest of
      Left why -> hPutStrLn stderr why >> exitWith (ExitFailure 2)
      Right options -> do
        attempted <- try (dispatch command path options)
        case attempted of
          Right code -> exitCode code
          Left (e :: SomeException) -> case fromException e :: Maybe AsyncException of
            Just UserInterrupt -> hPutStrLn stderr "Interrupted; inspect the partial report or recover the journal." >> exitWith (ExitFailure 130)
            Just ThreadKilled -> exitWith (ExitFailure 130)
            _ -> hPutStrLn stderr (diagnostic e) >> exitWith (ExitFailure 2)
    _ -> hPutStrLn stderr "Expected check, list, run, or report and a path. Use --help." >> exitWith (ExitFailure 2)

parseOptions :: String -> Options -> [String] -> Either String Options
parseOptions _ options [] = Right options
parseOptions command (Options _ color cases tags output jobs recover) ("--json" : rest) = parseOptions command (Options True color cases tags output jobs recover) rest
parseOptions command (Options json _ cases tags output jobs recover) ("--color" : color : rest)
  | color `elem` ["auto", "always", "never"] = parseOptions command (Options json color cases tags output jobs recover) rest
parseOptions "run" (Options json color cases tags output jobs recover) ("--case" : ident : rest) = parseOptions "run" (Options json color (cases ++ [Text.pack ident]) tags output jobs recover) rest
parseOptions "run" (Options json color cases tags output jobs recover) ("--tag" : tag : rest) = parseOptions "run" (Options json color cases (tags ++ [Text.pack tag]) output jobs recover) rest
parseOptions "run" (Options json color cases tags _ jobs recover) ("--output" : path : rest) = parseOptions "run" (Options json color cases tags (Just path) jobs recover) rest
parseOptions "run" (Options json color cases tags output _ recover) ("--jobs" : value : rest) = case readMaybe value of
  Just jobs | jobs == 1 -> parseOptions "run" (Options json color cases tags output jobs recover) rest
  _ -> Left "--jobs currently supports 1; parallel scheduling is not available yet"
parseOptions "report" (Options json color cases tags output jobs _) ("--recover" : rest) = parseOptions "report" (Options json color cases tags output jobs True) rest
parseOptions _ _ (unknown : _) = Left ("Unknown, incomplete, or unsupported option: " ++ unknown)

dispatch :: String -> FilePath -> Options -> IO Int
dispatch "report" path (Options json color _ _ _ _ recover) = do
  stored <- (if recover then recoverReport path else readReport path) >>= either throwIO pure
  if json then LBS.putStrLn (encode (reportJSON stored)) else case stored of StoredReport {result} -> render color result
  pure 0
dispatch command path (Options json color cases tags output _ _) = do
  manifest <- readManifest path >>= either (throwIO . ConfigurationFailure) pure
  let campaign = manifestCampaign manifest
      definitions = campaignCases campaign
  case command of
    "list" -> do
      if json
        then LBS.putStrLn (encode (object ["schemaVersion" .= (1 :: Int), "cases" .= map caseDefinitionJSON definitions]))
        else forM_ definitions $ \CaseDefinition {caseId, tags = caseTags, selector, expectation, description} ->
          putStrLn (Text.unpack (caseIdText caseId) ++ "  tags=" ++ show (Set.toAscList caseTags) ++ " selector=" ++ show selector ++ " expect=" ++ show expectation ++ "\n  " ++ Text.unpack description)
      pure 0
    "check" -> do
      checks <- checkManifest manifest >>= either (throwIO . ConfigurationFailure) pure
      if json
        then
          LBS.putStrLn
            ( encode
                ( object
                    [ "schemaVersion" .= (1 :: Int),
                      "checksPerformed" .= (["static-validation", "command-availability", "isolated-edit-applicability"] :: [Text]),
                      "testsExecuted" .= False,
                      "cases" .= [object ["id" .= caseIdText caseId, "applicable" .= applicable, "diagnostics" .= diagnostics] | Applicability {caseId, applicable, diagnostics} <- checks]
                    ]
                )
            )
        else do
          putStrLn "Checked structure, command availability and isolated edit applicability. Tests and discovery were not run."
          forM_ checks $ \Applicability {caseId, applicable, diagnostics} -> putStrLn (Text.unpack (caseIdText caseId) ++ if applicable then ": applicable" else ": " ++ show diagnostics)
      pure (if all (\Applicability {applicable} -> applicable) checks then 0 else 2)
    "run" -> do
      selected <- either (throwIO . ConfigurationFailure) pure (selectDefinitions cases tags definitions)
      let directory = maybe (manifestSourceRoot manifest </> "mutation-results") id output
          options =
            RunOptions
              (manifestSourceRoot manifest)
              directory
              (manifestPolicy manifest)
              (Just selected)
              (\case CaseStarted i -> hPutStrLn stderr ("running " ++ Text.unpack (caseIdText i)); _ -> pure ())
              (const (pure ()))
      result <- runCampaign options campaign
      if json
        then LBS.putStrLn (encode (object ["schemaVersion" .= (1 :: Int), "reportPath" .= (directory </> "report.json"), "selectionRule" .= String "union within filter kind, intersection across case/tag kinds", "result" .= runResultJSON result]))
        else render color result >> putStrLn ("Evidence: " ++ directory </> "report.json")
      pure (exitCodeFor result)
    _ -> error "validated command dispatch"

-- | Union repeated values within a filter kind; intersect the case and tag sets.
-- Unknown explicit IDs and empty intersections are configuration errors.
selectDefinitions :: [Text] -> [Text] -> [CaseDefinition] -> Either ConfigError SelectedCases
selectDefinitions requested tags definitions = do
  ids <- mapM mkCaseId requested
  let known = [caseId | CaseDefinition {caseId} <- definitions]
  unless (all (`elem` known) ids) (Left (ConfigError "case" "unknown requested case ID"))
  mkSelectedCases
    [ caseId
    | CaseDefinition {caseId, tags = caseTags} <- definitions,
      (null ids || caseId `elem` ids) && (null tags || not (Set.null (Set.intersection (Set.fromList tags) caseTags)))
    ]

-- | Infrastructure has precedence because RunStatus is library-owned.
exitCodeFor :: RunResult -> Int
exitCodeFor RunResult {status} = case status of RunPassed -> 0; RunFailed -> 1; RunUntrustworthy -> 2; RunInterrupted -> 130

exitCode :: Int -> IO ()
exitCode 0 = exitSuccess
exitCode n = exitWith (ExitFailure n)

render :: String -> RunResult -> IO ()
render color RunResult {results, status, score, failures} = do
  terminal <- hIsTerminalDevice stdout
  let colored = color == "always" || color == "auto" && terminal
      paint text = if colored then "\ESC[" ++ (if status == RunPassed then "32" else "31") ++ "m" ++ text ++ "\ESC[0m" else text
      counts = Map.fromListWith (+) [(show verdict, 1 :: Int) | CaseResult {verdict} <- results]
  putStrLn (paint (show status) ++ "  " ++ show (Map.toAscList counts))
  forM_ results $ \CaseResult {caseId, verdict, reason, evidence = CaseEvidence {stages}} -> do
    putStrLn (Text.unpack (caseIdText caseId) ++ ": " ++ show verdict ++ " — " ++ Text.unpack reason)
    forM_ stages $ \StageEvidence {transcript} -> unless (Text.null transcript) (putStrLn ("  witness: " ++ Text.unpack transcript))
  forM_ score $ \(SemanticScore caught total complete) -> putStrLn ("Semantic detections: " ++ show caught ++ "/" ++ show total ++ if complete then "" else " (incomplete)")
  forM_ failures (putStrLn . ("Run failure: " ++) . show)

help :: String
help =
  unlines
    [ "heni — deliberate mutation testing with attributable evidence",
      "",
      "Usage:",
      "  heni check MANIFEST [--json]",
      "  heni list MANIFEST [--json]",
      "  heni run MANIFEST [--case ID] [--tag TAG] [--output DIRECTORY] [--jobs 1] [--json]",
      "  heni report REPORT.json [--json]",
      "  heni report DIRECTORY --recover [--json]",
      "",
      "Selection:",
      "  Repeated filters use union within each kind and intersection across case/tag kinds.",
      "  Unknown explicit IDs and empty selection fail. Manifest paths resolve from its location.",
      "  --output is an explicit caller-relative path; the default is SOURCE/mutation-results.",
      "",
      "Presentation:",
      "  --color auto|always|never  Applies to human output only; redirected auto output has no ANSI.",
      "  --json                   JSON on stdout, progress and errors on stderr.",
      "  --help                   Show this help.",
      "  --version                Show the source-package version without Git.",
      "",
      "Checks and exits:",
      "  check runs static/availability/applicability checks, never tests or discovery.",
      "  run: 0 met contract; 1 failed contract; 2 configuration/infrastructure; SIGINT 130.",
      "  report renders stored evidence only; recovery never resumes commands.",
      "  Runs require a new output directory. Inspect report.json or recover journal.jsonl after interruption."
    ]

diagnostic :: SomeException -> String
diagnostic e = case fromException e of
  Just (ConfigurationFailure (ConfigError field message)) -> Text.unpack field ++ ": " ++ Text.unpack message
  Nothing -> case fromException e of
    Just (ReportError message) -> Text.unpack message
    Nothing -> displayException e
