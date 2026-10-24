module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Exception hiding (handle)
import Control.Monad (forM_, unless, when)
import Data.Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.List (isInfixOf, isPrefixOf)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Heni.Cli (exitCodeFor, selectDefinitions)
import Paths_heni_cli (getDataFileName)
import System.Directory qualified as Dir
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.Posix.Signals (sigINT, sigKILL, signalProcess)
import System.Posix.Temp (mkdtemp)
import System.Process (readProcessWithExitCode)
import System.Process qualified as P
import System.Timeout (timeout)
import Test.Heni

assert' :: String -> Bool -> IO ()
assert' name good = unless good (error name)

checked :: (Show e) => Either e a -> a
checked = either (error . show) id

main :: IO ()
main = bracket (Dir.getTemporaryDirectory >>= \tmp -> mkdtemp (tmp </> "heni-cli-test-")) Dir.removePathForcibly $ \root -> do
  corpus <- getDataFileName "test/corpus"
  names <- Dir.listDirectory corpus
  forM_ names $ \name -> do
    content <- BS.readFile (corpus </> name)
    assert' ("shared schema/decoder corpus: " ++ name) ((case decodeManifest content of Right _ -> True; Left _ -> False) == ("valid-" `isPrefixOf` name))
  let definition ident tags old new = object ["id" .= (ident :: String), "description" .= String "Detect the intended fault", "tags" .= (tags :: [String]), "edits" .= [object ["kind" .= String "replace", "path" .= String "input", "old" .= (old :: String), "new" .= (new :: String)]], "build" .= String "build", "test" .= String "test", "expect" .= object ["kind" .= String "diagnostic", "stage" .= String "test", "exitCode" .= (1 :: Int), "outputContains" .= String "capacity rule violated"]]
      value =
        object
          [ "schemaVersion" .= (1 :: Int),
            "sourceRoot" .= String "source",
            "commands"
              .= object
                [ "build" .= object ["executable" .= String "heni-fixture", "arguments" .= (["exit", "0"] :: [String])],
                  "test" .= object ["executable" .= String "heni-fixture", "arguments" .= (["check", "input", "diagnostic"] :: [String])]
                ],
            "cases" .= [definition "caught" ["regression"] "anchor" "mutant", definition "survivor" ["example"] "anchor" "harmless"]
          ]
      bytes = LBS.toStrict (encode value)
      manifestPath = root </> "heni.json"
      cli args = readProcessWithExitCode "heni" args ""
  Dir.createDirectory (root </> "source")
  BS.writeFile (root </> "source/input") "anchor\n"
  BS.writeFile manifestPath bytes
  manifest <- readManifest manifestPath >>= either (error . show) pure
  let definitions = campaignCases (manifestCampaign manifest)
  assert' "case union and tag intersection" (fmap selectedCaseIds (selectDefinitions ["caught", "caught", "survivor"] ["regression"] definitions) == Right [checked (mkCaseId "caught")])
  assert' "unknown explicit case" (case selectDefinitions ["absent"] [] definitions of Left _ -> True; _ -> False)
  assert' "empty selection" (case selectDefinitions [] ["absent"] definitions of Left _ -> True; _ -> False)
  (versionExit, version, _) <- cli ["--version"]
  assert' "archive-safe version" (versionExit == ExitSuccess && "heni 0.1.0.0" `isInfixOf` version)
  (helpExit, help, _) <- cli ["--help"]
  assert' "help selection/exit contract" (helpExit == ExitSuccess && "intersection" `isInfixOf` help && "SIGINT 130" `isInfixOf` help)
  (checkExit, checkOutput, _) <- cli ["check", manifestPath, "--json"]
  assert' "check states it did not execute tests" (checkExit == ExitSuccess && case eitherDecodeStrict (Text.encodeUtf8 (Text.pack checkOutput)) :: Either String Value of Right (Object o) -> KM.lookup "testsExecuted" o == Just (Bool False); _ -> False)
  (listExit, listing, _) <- cli ["list", manifestPath, "--json"]
  assert' "list is JSON" (listExit == ExitSuccess && case eitherDecodeStrict (Text.encodeUtf8 (Text.pack listing)) :: Either String Value of Right _ -> True; _ -> False)
  library <- runCampaign (RunOptions (manifestSourceRoot manifest) (root </> "library") (manifestPolicy manifest) (Just (checked (selectDefinitions ["caught"] [] definitions))) (const (pure ())) (const (pure ()))) (manifestCampaign manifest)
  (caughtExit, runOutput, progress) <- cli ["run", manifestPath, "--case", "caught", "--output", root </> "cli", "--json", "--color", "always"]
  assert' "caught exit and clean machine stdout" (caughtExit == ExitSuccess && not ('\ESC' `elem` runOutput) && "running caught" `isInfixOf` progress)
  cliStored <- readReport (root </> "cli/report.json") >>= either (error . show) pure
  let signature RunResult {results} = [(caseIdText caseId, verdict, [(stage, outcome) | StageEvidence {stage, outcome} <- stages]) | CaseResult {caseId, verdict, evidence = CaseEvidence {stages}} <- results]
  assert' "library/CLI share stage decisions and verdicts" (case cliStored of StoredReport {result} -> signature result == signature library && exitCodeFor result == 0)
  (survivorExit, human, _) <- cli ["run", manifestPath, "--case", "survivor", "--output", root </> "survivor"]
  assert' "survivor exit and redirected output without ANSI" (survivorExit == ExitFailure 1 && not ('\ESC' `elem` human))
  (emptyExit, _, _) <- cli ["run", manifestPath, "--tag", "absent", "--output", root </> "empty"]
  assert' "empty run fails by default" (emptyExit == ExitFailure 2)
  Dir.renameDirectory (root </> "cli") (root </> "moved")
  (reportExit, storedOutput, _) <- cli ["report", root </> "moved/report.json", "--json"]
  assert' "moved evidence renders" (reportExit == ExitSuccess && not (null storedOutput))
  (recoveryExit, _, _) <- cli ["report", root </> "moved", "--recover"]
  assert' "explicit recovery renders without execution" (recoveryExit == ExitSuccess)
  let invalids =
        [ Text.replace "\"schemaVersion\":1" "\"schemaVersion\":999" (Text.decodeUtf8 bytes),
          Text.replace "\"schemaVersion\":1" "\"schemaVersion\":1,\"schemaVersion\":1" (Text.decodeUtf8 bytes),
          Text.replace "\"schemaVersion\":1" "\"schemaVersion\":1,\"\\u0073chemaVersion\":1" (Text.decodeUtf8 bytes),
          Text.replace "\"executable\":\"heni-fixture\"" "\"executable\":\"heni-fixture\",\"timeuotSeconds\":2" (Text.decodeUtf8 bytes),
          Text.replace "\"executable\":\"heni-fixture\"" "\"executable\":\"heni-fixture\",\"timeoutSeconds\":0" (Text.decodeUtf8 bytes),
          Text.replace "\"executable\":\"heni-fixture\"" "\"executable\":\"heni-fixture\",\"arguments\":null" (Text.decodeUtf8 bytes),
          Text.replace "\"path\":\"input\"" "\"path\":\"../escape\"" (Text.decodeUtf8 bytes),
          Text.replace "\"build\":\"build\"" "\"build\":\"absent\"" (Text.decodeUtf8 bytes)
        ]
  forM_ invalids $ \invalid -> assert' "invalid manifest rejected" (case decodeManifest (Text.encodeUtf8 invalid) of Left _ -> True; _ -> False)
  -- Applicability checks and listing do not execute a command with visible effects.
  let sentinel = root </> "must-not-execute"
      noExecute = object ["schemaVersion" .= (1 :: Int), "sourceRoot" .= String "source", "commands" .= object ["build" .= object ["executable" .= String "heni-fixture", "arguments" .= ["counter", sentinel]], "test" .= object ["executable" .= String "heni-fixture", "arguments" .= (["exit", "0"] :: [String])]], "cases" .= [definition "caught" [] "anchor" "mutant"]]
  LBS.writeFile (root </> "no-execute.json") (encode noExecute)
  _ <- cli ["check", root </> "no-execute.json"]
  _ <- cli ["list", root </> "no-execute.json"]
  Dir.doesFileExist sentinel >>= assert' "check/list never execute tests or builds" . not
  let interruptMarker = root </> "interrupted-child.pid"
      interruptManifest =
        object
          [ "schemaVersion" .= (1 :: Int),
            "sourceRoot" .= String "source",
            "commands"
              .= object
                [ "build" .= object ["executable" .= String "heni-fixture", "arguments" .= (["exit", "0"] :: [String])],
                  "test" .= object ["executable" .= String "heni-fixture", "arguments" .= ["check", "input", "timeout", interruptMarker]]
                ],
            "cases" .= [definition "caught" [] "anchor" "mutant"]
          ]
  LBS.writeFile (root </> "interrupt.json") (encode interruptManifest)
  let process = (P.proc "heni" ["run", root </> "interrupt.json", "--output", root </> "interrupted"]) {P.std_out = P.Inherit, P.std_err = P.Inherit}
  P.withCreateProcess process $ \_ _ _ handle -> do
    let waitReady = do
          exists <- Dir.doesFileExist interruptMarker
          unless exists (threadDelay 5000 >> waitReady)
        stopOwned = do
          markerExists <- Dir.doesFileExist interruptMarker
          when markerExists $ do
            pid <- read <$> readFile interruptMarker
            _ <- try (signalProcess sigKILL pid) :: IO (Either IOException ())
            pure ()
    ( do
        ready <- timeout 5000000 waitReady
        assert' "CLI interruption handshake" (ready == Just ())
        pid <- P.getPid handle >>= maybe (error "missing owned CLI PID") pure
        signalProcess sigINT pid
        exited <- timeout 5000000 (P.waitForProcess handle)
        assert' "SIGINT uses 130 after finalization" (exited == Just (ExitFailure 130))
        partial <- readReport (root </> "interrupted/report.json")
        assert' "SIGINT retains complete selected ledger" (case partial of Right StoredReport {result = RunResult {status = RunInterrupted, results = [CaseResult {verdict = NotRun}]}} -> True; _ -> False)
      )
      `finally` stopOwned
  putStrLn "Strict manifest boundary, CLI exits, selection and library parity passed"
