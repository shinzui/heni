module Main (main) where

import Control.Exception
import Control.Monad (forM, forM_, unless)
import Data.Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (Pair)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.IO qualified as Text
import Data.Version (showVersion)
import GHC.Clock (getMonotonicTimeNSec)
import Legacy
import Paths_heni (getDataFileName)
import System.Directory qualified as Dir
import System.Environment (getArgs, lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO (BufferMode (..), hSetBuffering, stdout)
import System.Info qualified as Platform
import System.Posix.Signals (sigABRT)
import System.Posix.Temp (mkdtemp)
import System.Process (readProcessWithExitCode)
import System.Timeout (timeout)
import Test.Heni
import Test.Heni.Workspace

checked :: (Show e) => Either e a -> a
checked = either (error . show) id

assert' :: String -> Bool -> IO ()
assert' why good = unless good (error why)

jsonField :: Key -> Value -> Value
jsonField key (Object o) = maybe Null id (KM.lookup key o)
jsonField _ _ = Null

set :: Key -> Value -> Value -> Value
set key value (Object o) = Object (KM.insert key value o)
set _ _ other = other

signature :: RunResult -> [(Text, Verdict, Maybe DetectionKind, [(Stage, ProcessOutcome)])]
signature RunResult {results} = [(caseIdText caseId, verdict, detection, [(stage, outcome) | StageEvidence {stage, outcome} <- stages]) | CaseResult {caseId, verdict, detection, evidence = CaseEvidence {stages}} <- results]

main :: IO ()
main = do
  hSetBuffering stdout LineBuffering
  timeout 1200000000 suite >>= \case Nothing -> error "migration watchdog (20 minutes)"; Just () -> pure ()

suite :: IO ()
suite = bracket (Dir.getTemporaryDirectory >>= \p -> mkdtemp (p </> "heni-migration-")) preserveAndRemove $ \root -> do
  cliExecutable <- lookupEnv "HENI_CLI_EXE" >>= maybe (error "set HENI_CLI_EXE to the separately built heni-cli executable") pure
  args <- getArgs
  let families = if "--rich-only" `elem` args then [] else ["replacement", "patch-catalogue", "generated-code", "diagnostic-checker"]
  records <- forM families $ \family -> do
    putStrLn ("migration family: " ++ family)
    sourceManifest <- getDataFileName ("examples/migrations/" ++ family ++ "/heni.json")
    original <- BS.readFile sourceManifest >>= either (error . show) pure . eitherDecodeStrict
    legacyStart <- getMonotonicTimeNSec
    legacyCaught <- runLegacy family (takeDirectory sourceManifest)
    legacyEnd <- getMonotonicTimeNSec
    assert' (family ++ " legacy intended detection") legacyCaught
    legacyWrong <- if family == "replacement" then Just <$> runLegacy "unrelated-compile-failure" (takeDirectory sourceManifest) else pure Nothing
    assert' "exit-only comparison demonstrates unrelated compiler false positive" (family /= "replacement" || legacyWrong == Just True)
    withSnapshot (takeDirectory sourceManifest) defaultSnapshotPolicy $ \snapshot -> withWorkspace snapshot $ \outer -> do
      let source = workspaceRoot outer
          edits path before after = [Replace (checked (mkRelativeTarget path)) before after 1]
          (ident, target, witness) = case family of
            "generated-code" -> ("generated-guard", "model.txt", "generated capacity: FAIL")
            "diagnostic-checker" -> ("invalid-capacity", "policy.txt", "policy.capacity: maximum must be positive")
            _ -> ("guard-bypass", "src/Capacity.hs", "rejects full capacity: FAIL")
          (old, new) = case family of "generated-code" -> ("mode=strict", "mode=open"); "diagnostic-checker" -> ("capacity=10", "capacity=-1"); _ -> ("used < limit", "True")
          base cid change expect = CaseDefinition (checked (mkCaseId cid)) "Fixture-specific migration" Set.empty change (checked (mkCommandId "build")) (Just (checked (mkCommandId "test"))) Nothing expect GenericCommands
          expected = Diagnostic Test 1 witness
      patch <- if family == "patch-catalogue" then Just <$> Text.readFile (source </> "patches/guard-bypass.patch") else pure Nothing
      survivorPatch <- if family == "patch-catalogue" then Just <$> Text.readFile (source </> "patches/survivor.patch") else pure Nothing
      let caught = base ident (maybe (edits target old new) (pure . Patch) patch) expected
          survivor = base "surviving-label" (maybe (edits target "baseline" "variant") (pure . Patch) survivorPatch) expected
          compileError = base "unrelated-compile-error" (edits target "used < limit" "missingCapacityGuard") expected
          rejection = base "expected-build-rejection" (edits target "used < limit" "missingCapacityGuard") (BuildRejection 1 "not in scope")
          portableCases = [caught, survivor] ++ (if family == "replacement" then [compileError, rejection] else [])
          value = set "execution" (object ["workers" .= (2 :: Int), "baselineReuse" .= object ["toolchain" .= String "local GHC/Cabal fixture contract; no external state"]]) (set "cases" (toJSON (map caseDefinitionJSON portableCases)) original)
          manifestPath = source </> "heni.json"
      LBS.writeFile manifestPath (encode value)
      manifest <- readManifest manifestPath >>= either (error . show) pure
      let customGenerated definition = case definition of
            CaseDefinition cid desc tags _ build test selector expect mode ->
              ( CaseDefinition cid desc tags [CustomEdit "generator-input"] build test selector expect mode,
                CaseHooks
                  [ ( "generator-input",
                      \WorkspaceOps {readTarget, writeTarget} -> do
                        let path = checked (mkRelativeTarget "model.txt")
                        content <- readTarget path
                        unless (Text.count "mode=strict" content == 1) (ioError (userError "generator input anchor mismatch"))
                        writeTarget path (Text.replace "mode=strict" "mode=open" content)
                    )
                  ]
                  Nothing
                  Nothing
              )
          typed = [if family == "generated-code" && index == 0 then customGenerated d else (d, noHooks) | (index, d) <- zip [0 :: Int ..] portableCases]
          campaign = checked (mkCampaign (campaignCommands (manifestCampaign manifest)) typed)
      start <- getMonotonicTimeNSec
      library <- runCampaign (defaultRunOptions source (root </> family </> "library")) campaign
      middle <- getMonotonicTimeNSec
      (exit, _, err) <- readProcessWithExitCode cliExecutable ["run", manifestPath, "--jobs", "2", "--output", root </> family </> "cli", "--json"] ""
      end <- getMonotonicTimeNSec
      assert' (family ++ " expected nonpassing survivor exit: " ++ err) (exit == ExitFailure 1)
      cliReport@StoredReport {result = cli} <- readReport (root </> family </> "cli/report.json") >>= either (error . show) pure
      libReport <- readReport (root </> family </> "library/report.json") >>= either (error . show) pure
      assert' (family ++ " typed/manifest semantic parity: " ++ show (signature library, signature cli)) (signature library == signature cli)
      assert' (family ++ " intended/surviving variants") (map (\(_, v, _, _) -> v) (signature library) == [Caught, Survived] ++ (if family == "replacement" then [UnexpectedBuildFailure, Caught] else []))
      let StoredReport {metadata = lm} = libReport; StoredReport {metadata = cm} = cliReport
      assert' "both paths capture identical selected source bytes" (jsonField "identity" (jsonField "snapshot" lm) == jsonField "identity" (jsonField "snapshot" cm))
      whenGenerated family $ do
        output <- BS.readFile (root </> family </> "library/generated-guard-candidate-build.stdout.log")
        assert' "mutated generator input reaches compiled artifact" ("artifact: admits used limit = True" `BS.isInfixOf` output)
      -- Reading a stale schema is a diagnostic action, never a rerun.
      LBS.writeFile (root </> family </> "stale-report.json") (encode (set "schemaVersion" (Number 999) (reportJSON cliReport)))
      stale <- readReport (root </> family </> "stale-report.json")
      assert' "stale report schema is rejected" (case stale of Left _ -> True; _ -> False)
      pure (object ["family" .= family, "legacyIntendedCaught" .= legacyCaught, "legacyUnrelatedCompileAccepted" .= legacyWrong, "legacySeconds" .= seconds legacyStart legacyEnd, "typedFreshSeconds" .= seconds start middle, "cliParallelReuseSeconds" .= seconds middle end, "outcomes" .= [show verdict | CaseResult {verdict} <- case library of RunResult {results} -> results], "typedReport" .= reportJSON libReport, "cliReport" .= reportJSON cliReport])
  rich <- richTrials cliExecutable root
  let output = object ["trialSelection" .= String (if null families then "rich-only" else "complete"), "operator" .= String "automated agent-authored trial; no human usability timing claimed", "platform" .= object ["os" .= Platform.os, "arch" .= Platform.arch, "compilerVersion" .= showVersion Platform.compilerVersion], "families" .= records, "richer" .= rich]
  destination <- lookupEnv "HENI_MIGRATION_RESULTS"
  forM_ destination $ \path -> do
    Dir.createDirectoryIfMissing True (takeDirectory path)
    let evidenceDirectory = takeDirectory path </> takeFileName root
    LBS.writeFile path (encode (set "evidenceDirectory" (String (Text.pack evidenceDirectory)) output))
  putStrLn (if null families then "Richer evidence trial passed" else "Four migration families, typed/CLI parity, precise negatives and richer evidence passed")
  where
    seconds start end = fromIntegral (end - start) / 1e9 :: Double
    whenGenerated family action = if family == "generated-code" then action else pure ()

richTrials :: FilePath -> FilePath -> IO Value
richTrials cliExecutable root = do
  let source = root </> "rich-source"
      build = "build" :: Text
      command args budget = object ["executable" .= String "heni-evidence-fixture", "arguments" .= (args :: [String]), "timeoutSeconds" .= (budget :: Double)]
      namedCommand mode = command ["protocol", "input", mode] 5
      replace old new = object ["kind" .= String "replace", "path" .= String "input", "old" .= (old :: Text), "new" .= (new :: Text)]
      named replay = object ["kind" .= String "named-tests", "failures" .= (["suite/intended"] :: [Text]), "replayRequired" .= replay]
      define :: Text -> Text -> Value -> Value -> [Value] -> [Pair] -> Value
      define cid test expect adapter edits extras = object (["id" .= (cid :: Text), "description" .= String "Combined evidence migration", "build" .= build, "test" .= (test :: Text), "expect" .= expect, "adapter" .= adapter, "edits" .= edits] ++ extras)
      diagnostic = object ["kind" .= String "diagnostic", "stage" .= String "test", "exitCode" .= (1 :: Int), "outputContains" .= String "capacity rule violated"]
      normal cid test = define cid test (named False) (String "heni-v1") [replace "anchor" "mutant"]
      resource :: Text -> Text -> Text -> Value
      resource name setup teardown = object ["name" .= name, "identity" .= String "fixture", "version" .= String "v1", "epoch" .= String "clean", "setup" .= setup, "reset" .= build, "teardown" .= teardown]
      cases = [normal "intended" "intended" [], normal "wrong-named" "wrong" [], normal "empty-selection" "intended" ["selector" .= String "absent"], define "stale-edit" "generic" diagnostic Null [replace "missing" "mutant"] [], define "hang" "hang" diagnostic Null [replace "anchor" "mutant"] [], normal "setup-failed" "intended" ["resources" .= (["SETUP"] :: [Text])], normal "teardown-failed" "intended" ["resources" .= (["TEARDOWN"] :: [Text])], define "replay" "replay" (named True) (String "heni-v1") [replace "anchor" "mutant"] [], define "crash" "crash" (object ["kind" .= String "crash", "signal" .= (fromIntegral sigABRT :: Int), "probe" .= String "operation-reached"]) Null [replace "anchor" "mutant"] [], define "control" "intended" (object ["kind" .= String "control"]) (String "heni-v1") [] []]
      value = object ["schemaVersion" .= (1 :: Int), "execution" .= object ["workers" .= (2 :: Int), "baselineReuse" .= object ["toolchain" .= String "standalone protocol fixture/v1", "adapter" .= String "fixture/v1"]], "commands" .= object ["build" .= command ["exit", "0"] 5, "fail" .= command ["exit", "1"] 5, "intended" .= namedCommand "intended", "wrong" .= namedCommand "wrong", "replay" .= namedCommand "replay", "crash" .= command ["crash", "input", "good"] 5, "generic" .= object ["executable" .= String "heni-fixture", "arguments" .= (["check", "input", "diagnostic"] :: [String])], "hang" .= object ["executable" .= String "heni-fixture", "arguments" .= (["check", "input", "timeout"] :: [String]), "timeoutSeconds" .= (0.5 :: Double)]], "resources" .= [resource ("SETUP" :: Text) ("fail" :: Text) build, resource ("TEARDOWN" :: Text) build ("fail" :: Text)], "cases" .= cases]
  Dir.createDirectory source
  BS.writeFile (source </> "input") "anchor"
  LBS.writeFile (source </> "heni.json") (encode value)
  manifest <- readManifest (source </> "heni.json") >>= either (error . show) pure
  lib <- runCampaign ((manifestRunOptions (root </> "rich-library") manifest) {workers = 1, reusePolicy = Fresh}) (manifestCampaign manifest)
  (exit, _, err) <- readProcessWithExitCode cliExecutable ["run", source </> "heni.json", "--output", root </> "rich-cli", "--json"] ""
  assert' ("rich infrastructure exit: " ++ err) (exit == ExitFailure 2)
  report@StoredReport {result = cli} <- readReport (root </> "rich-cli/report.json") >>= either (error . show) pure
  let issues RunResult {results} = [(caseIdText caseId, infrastructureErrors, cleanupErrors) | CaseResult {caseId, evidence = CaseEvidence {infrastructureErrors, cleanupErrors}} <- results]
  assert' ("richer typed/CLI parity: " ++ show (signature lib, signature cli) ++ "; issues: " ++ show (issues lib, issues cli)) (signature lib == signature cli)
  assert' "richer outcomes preserve named, replay, crash, resource and control meaning" (map (\(_, v, _, _) -> v) (signature lib) == [Caught, WrongFailure, NotRun, InvalidMutation, TimedOut, InfrastructureError, InfrastructureError, Caught, Caught, Caught])
  pure (reportJSON report)

preserveAndRemove :: FilePath -> IO ()
preserveAndRemove root = do
  destination <- lookupEnv "HENI_MIGRATION_RESULTS"
  forM_ destination $ \path -> do
    Dir.createDirectoryIfMissing True (takeDirectory path)
    let evidenceDirectory = takeDirectory path </> takeFileName root
    copyFixture root evidenceDirectory
    putStrLn ("migration evidence retained: " ++ evidenceDirectory)
  Dir.removePathForcibly root
