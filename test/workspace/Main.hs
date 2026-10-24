module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Exception
import Control.Monad (forM_, unless, when)
import Data.ByteString qualified as BS
import Data.IORef
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import System.Directory qualified as Dir
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.FilePath ((</>))
import System.Posix.Files qualified as Posix
import System.Posix.Temp (mkdtemp)
import System.Process qualified as Process
import System.Timeout (timeout)
import Test.Heni
import Test.Heni.Edit
import Test.Heni.Workspace

assert' :: String -> Bool -> IO ()
assert' message condition = unless condition (error message)

checked :: (Show e) => Either e a -> a
checked = either (error . show) id

target :: FilePath -> RelativeTarget
target = checked . mkRelativeTarget

caseWith :: [Edit] -> CaseDefinition
caseWith edits =
  CaseDefinition
    (checked (mkCaseId "workspace-test"))
    "Test checked mutations"
    Set.empty
    edits
    (checked (mkCommandId "build"))
    (Just (checked (mkCommandId "test")))
    Nothing
    (Diagnostic Test 1 "witness")
    GenericCommands

withTree :: (FilePath -> IO a) -> IO a
withTree action = bracket (Dir.getTemporaryDirectory >>= \tmp -> mkdtemp (tmp </> "heni-test-")) Dir.removePathForcibly action

-- Test-only bounded helper until EP-3 supplies the production supervisor. Git
-- doesn't spawn descendants for apply; timeout cancels its process bracket.
gitRunner :: PatchRunner
gitRunner workspace args = do
  let root = workspaceRoot workspace
  result <- timeout 5000000 (Process.readCreateProcessWithExitCode (Process.proc "git" ("-C" : root : args)) "")
  pure $ case result of
    Just (ExitSuccess, _, _) -> Right ()
    Just (_, out, err) -> Left (Text.pack (out ++ err))
    Nothing -> Left "git apply timeout"

main :: IO ()
main = withTree $ \source -> do
  BS.writeFile (source </> "dirty.txt") "anchor\n"
  BS.writeFile (source </> "untracked.bin") (BS.pack [0, 255, 1])
  Dir.createDirectory (source </> "dist-newstyle")
  BS.writeFile (source </> "dist-newstyle/ignored") "build"
  Dir.createDirectory (source </> "mutation-results")
  BS.writeFile (source </> "mutation-results/report.json") "ignored"
  withSnapshot source defaultSnapshotPolicy $ \snapshot -> do
    let files = snapshotFiles snapshot
        edit = Replace (target "dirty.txt") "anchor" "changed" 1
        run edits = withEditedWorkspace gitRunner noHooks snapshot (caseWith edits) (\w e -> (,) <$> BS.readFile (workspaceRoot w </> "dirty.txt") <*> pure e)
    assert' "selected dirty/untracked bytes" (Map.size files == 2 && Map.member (target "untracked.bin") files)
    assert' "SHA256 identity" (Text.length (snapshotIdentity snapshot) == 64)
    withSnapshot source defaultSnapshotPolicy $ \again -> assert' "deterministic identity" (snapshotIdentity again == snapshotIdentity snapshot)
    result <- run [edit]
    assert' "checked replacement and touched inventory" (case result of Right ("changed\n", EditEvidence [FileChange {}]) -> True; _ -> False)
    original <- BS.readFile (source </> "dirty.txt")
    assert' "source untouched" (original == "anchor\n")
    withWorkspace snapshot $ \other -> do
      originalOther <- BS.readFile (workspaceRoot other </> "dirty.txt")
      assert' "other workspace pristine" (originalOther == "anchor\n")
    forM_ [[Replace (target "dirty.txt") "missing" "bad" 1], [Replace (target "dirty.txt") "anchor" "x" 2], [edit, Replace (target "dirty.txt") "missing" "x" 1], [edit, Replace (target "dirty.txt") "changed" "anchor" 1]] $ \edits -> do
      failed <- run edits
      assert' "stale/ambiguous/partial/no-op rejected" (case failed of Left InvalidEdit {} -> True; _ -> False)
    malformed <- withEditedWorkspace gitRunner noHooks snapshot (caseWith [Replace (target "untracked.bin") "x" "y" 1]) (\_ _ -> pure ())
    assert' "UTF8 error is invalid edit" (case malformed of Left InvalidEdit {} -> True; _ -> False)
    -- No callback is published on partial failure.
    published <- newIORef False
    _ <- withEditedWorkspace gitRunner noHooks snapshot (caseWith [edit, Replace (target "dirty.txt") "missing" "bad" 1]) (\_ _ -> writeIORef published True)
    readIORef published >>= assert' "partial candidate unpublished" . not
    created <- withEditedWorkspace gitRunner noHooks snapshot (caseWith [Create (target "new.txt") "created", Delete (target "dirty.txt") "anchor\n"]) $ \_ (EditEvidence changes) -> pure (length changes)
    assert' "creation/deletion recorded" (created == Right 2)
    duplicateCreate <- withEditedWorkspace gitRunner noHooks snapshot (caseWith [Create (target "dirty.txt") "created"]) (\_ _ -> pure ())
    assert' "creation precondition" (case duplicateCreate of Left InvalidEdit {} -> True; _ -> False)
    let control = case caseWith [] of CaseDefinition i d ts es b t s _ mode -> CaseDefinition i d ts es b t s Control mode
    controlResult <- withEditedWorkspace gitRunner noHooks snapshot control (\_ (EditEvidence changes) -> pure (null changes))
    assert' "unchanged control accepted" (controlResult == Right True)
    withWorkspace snapshot $ \w -> do
      let WorkspaceOps {writeTarget} = workspaceOperations w
      writeTarget (target "dirty.txt") "changed"
      differs <- try (verifyWorkspace snapshot w) :: IO (Either WorkspaceError ())
      assert' "verification detects changes" (case differs of Left WorkspaceMismatch {} -> True; _ -> False)
      resetWorkspace snapshot w
      verifyWorkspace snapshot w
      withTree $ \outside -> do
        BS.writeFile (outside </> "victim") "safe"
        Posix.createSymbolicLink (outside </> "victim") (workspaceRoot w </> "escape")
        rejected <- try (writeTarget (target "escape") "bad") :: IO (Either WorkspaceError ())
        assert' "symlink write rejected" (case rejected of Left UnsafeSource {} -> True; _ -> False)
        BS.readFile (outside </> "victim") >>= assert' "outside bytes untouched" . (== "safe")
      -- A deleted owned root produces an observable reset failure.
      Dir.removePathForcibly (workspaceRoot w)
      reset <- try (resetWorkspace snapshot w) :: IO (Either IOException ())
      assert' "reset failure invalidates workspace" (case reset of Left _ -> True; _ -> False)
    let patch = "diff --git a/dirty.txt b/dirty.txt\n--- a/dirty.txt\n+++ b/dirty.txt\n@@ -1 +1 @@\n-anchor\n+patched\n"
    available <- Dir.findExecutable "git"
    required <- lookupEnv "HENI_REQUIRE_GIT"
    when (required == Just "1" && available == Nothing) (error "patch validation requires Git")
    case available of
      Nothing -> putStrLn "Git unavailable: optional positive patch checks skipped"
      Just _ -> do
        patched <- run [Patch patch]
        assert' "textual patch" (case patched of Right ("patched\n", _) -> True; _ -> False)
        stalePatch <- run [Patch (patch <> "diff --git a/missing b/missing\n--- a/missing\n+++ b/missing\n@@ -1 +1 @@\n-old\n+new\n")]
        assert' "partial patch discarded" (case stalePatch of Left InvalidEdit {} -> True; _ -> False)
        again <- run [edit]
        assert' "patch failure cannot contaminate next case" (case again of Right ("changed\n", _) -> True; _ -> False)
    unsafePatch <- run [Patch (Text.replace "--- a/dirty.txt" "--- a/../escape" patch)]
    assert' "all patch header paths checked" (case unsafePatch of Left InvalidEdit {} -> True; _ -> False)
    missingGit <- withEditedWorkspace (\_ _ -> throwIO (userError "git is unavailable")) noHooks snapshot (caseWith [Patch patch]) (\_ _ -> pure ())
    assert' "missing Git infrastructure capability" (case missingGit of Left EditInfrastructure {} -> True; _ -> False)
    let hooks = CaseHooks [("cancel", \_ -> threadDelay 10000000)] Nothing Nothing
    cancelled <- timeout 20000 (withEditedWorkspace gitRunner hooks snapshot (caseWith [CustomEdit "cancel"]) (\_ _ -> pure ()))
    assert' "cancellation bounded" (case cancelled of Nothing -> True; _ -> False)
    withWorkspace snapshot (verifyWorkspace snapshot)
    validateOutputLocation source defaultSnapshotPolicy (source </> "mutation-results")
    invalidOutput <- try (validateOutputLocation source defaultSnapshotPolicy (source </> "new-results")) :: IO (Either WorkspaceError ())
    assert' "nested output exclusion required" (case invalidOutput of Left _ -> True; _ -> False)
  withTree $ \outside -> do
    Posix.createSymbolicLink outside (source </> "source-link")
    rejected <- try (withSnapshot source defaultSnapshotPolicy (\_ -> pure ())) :: IO (Either WorkspaceError ())
    assert' "source symlink rejected" (case rejected of Left UnsafeSource {} -> True; _ -> False)
  putStrLn "Workspace isolation, transactional edits, patch and recovery checks passed"
