-- | Immutable source bytes and exclusive disposable working copies.
module Test.Heni.Workspace
  ( SourceSnapshot,
    SnapshotPolicy (..),
    defaultSnapshotPolicy,
    defaultExcludedNames,
    defaultExcludedPrefixes,
    Workspace,
    WorkspaceError (..),
    WorkspaceFinalizationError (..),
    FileEntry (..),
    withSnapshot,
    withWorkspace,
    workspaceRoot,
    snapshotIdentity,
    snapshotPolicy,
    snapshotFiles,
    verifyWorkspace,
    resetWorkspace,
    checkedWorkspacePath,
    validateOutputLocation,
  )
where

import Control.Exception (throwIO)
import Control.Monad (forM_, unless, when)
import Data.List (isPrefixOf)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory qualified as Dir
import System.FilePath (makeRelative, splitDirectories, (</>))
import Test.Heni.Case (RelativeTarget, targetPath)
import Test.Heni.Internal.Files

-- | Includes selected working-tree bytes (dirty and untracked), never implicit HEAD.
data SnapshotPolicy = SnapshotPolicy
  { includes :: ![RelativeTarget],
    excludes :: ![RelativeTarget]
  }
  deriving stock (Eq, Show)

-- | Empty includes means the root. Default excluded names apply at every depth.
defaultSnapshotPolicy :: SnapshotPolicy
defaultSnapshotPolicy = SnapshotPolicy [] []

-- | Stored in memory: callers cannot mutate snapshot bytes through a filesystem path.
data SourceSnapshot = SourceSnapshot !Text !SnapshotPolicy !Inventory

-- | Constructor hidden: only Heni allocates and owns a cleanup target.
newtype Workspace = Workspace FilePath

-- | SHA-256 over framed sorted names, bytes, executable bits and policy.
snapshotIdentity :: SourceSnapshot -> Text
snapshotIdentity (SourceSnapshot identity _ _) = identity

-- | Effective inclusion and exclusion choices.
snapshotPolicy :: SourceSnapshot -> SnapshotPolicy
snapshotPolicy (SourceSnapshot _ policy _) = policy

-- | Immutable selected bytes, including binary fixtures.
snapshotFiles :: SourceSnapshot -> Map.Map RelativeTarget FileEntry
snapshotFiles (SourceSnapshot _ _ files) = files

-- | Exclusive directory for consumer commands. This is not an OS sandbox.
workspaceRoot :: Workspace -> FilePath
workspaceRoot (Workspace root) = root

-- | Effective default directory/file names, recorded in snapshot identities.
defaultExcludedNames :: [FilePath]
defaultExcludedNames = [".git", "dist", "dist-newstyle", "cabal-dev", ".direnv", "result", "mutation-results", ".heni", ".DS_Store"]

-- | Name prefixes excluded at every depth.
defaultExcludedPrefixes :: [FilePath]
defaultExcludedPrefixes = ["result-", ".heni-"]

excludedBy :: SnapshotPolicy -> FilePath -> Bool
excludedBy (SnapshotPolicy ins outs) p = defaultExcluded || explicitExcluded || outsideSelection
  where
    parts = splitDirectories p
    defaultExcluded = any (\part -> part `elem` defaultExcludedNames || any (`isPrefixOf` part) defaultExcludedPrefixes) parts
    prefix a b = a == b || (a ++ "/") `isPrefixOf` b
    explicitExcluded = any (\t -> prefix (targetPath t) p) outs
    outsideSelection = not (null ins) && not (any (\t -> prefix p (targetPath t) || prefix (targetPath t) p) ins)

-- | Capture twice and require identical inventory; this detects ordinary concurrent
-- changes, but is not an atomic OS snapshot under adversarial writers.
withSnapshot :: FilePath -> SnapshotPolicy -> (SourceSnapshot -> IO a) -> IO a
withSnapshot root policy action = do
  canonical <- Dir.canonicalizePath root
  when (canonical == "/" || canonical == "/nix/store" || "/nix/store/" `isPrefixOf` canonical) (throwIO (UnsafeSource "source root is not a project directory"))
  symlink <- Dir.pathIsSymbolicLink root
  when symlink (throwIO (UnsafeSource "source root is a symlink"))
  let SnapshotPolicy {includes} = policy
  forM_ includes $ \target -> do
    path <- checkedPath canonical target
    exists <- Dir.doesPathExist path
    unless exists (throwIO (UnsafeSource ("included input does not exist: " <> Text.pack (targetPath target))))
  before <- inventory (excludedBy policy) canonical
  after <- inventory (excludedBy policy) canonical
  unless (before == after) (throwIO SourceChanged)
  action (SourceSnapshot (inventoryDigest (Text.pack (show policy ++ show defaultExcludedNames ++ show defaultExcludedPrefixes)) before) policy before)

-- | Bracket allocation and removal. Cleanup exceptions remain observable.
withWorkspace :: SourceSnapshot -> (Workspace -> IO a) -> IO a
withWorkspace (SourceSnapshot _ _ files) action = withOwnedDirectory ".heni-workspace-" $ \root -> do
  materialize root files
  action (Workspace root)

-- | Verify exact source inventory. Build outputs are deliberately excluded.
verifyWorkspace :: SourceSnapshot -> Workspace -> IO ()
verifyWorkspace (SourceSnapshot _ policy files) (Workspace root) = do
  actual <- inventory (excludedBy policy) root
  unless (actual == files) (throwIO (WorkspaceMismatch "workspace differs from pristine snapshot"))

-- | Reset only an opaque owned workspace, then independently verify it.
-- A thrown exception invalidates reuse; the caller must allocate a fresh copy.
resetWorkspace :: SourceSnapshot -> Workspace -> IO ()
resetWorkspace snap@(SourceSnapshot _ _ files) (Workspace root) = do
  -- Validate the root before listing or deleting anything.
  _ <- inventory (const True) root
  names <- Dir.listDirectory root
  mapM_ (Dir.removePathForcibly . (root </>)) names
  materialize root files
  verifyWorkspace snap (Workspace root)

-- | Validate every existing component before an operation; rejects symlink escapes.
checkedWorkspacePath :: Workspace -> RelativeTarget -> IO FilePath
checkedWorkspacePath (Workspace root) = checkedPath root

-- | Output under the source root is permitted only when the effective policy
-- excludes it. Ancestors and source-equal locations are always rejected.
validateOutputLocation :: FilePath -> SnapshotPolicy -> FilePath -> IO ()
validateOutputLocation source policy output = do
  s <- Dir.canonicalizePath source
  o <- Dir.canonicalizePath output
  let relative = makeRelative s o
      outputAncestor = o == s || (o ++ "/") `isPrefixOf` s
      outputInside = not (null relative) && not (".." `elem` splitDirectories relative) && not ("/" `isPrefixOf` relative)
  when
    (outputAncestor || (outputInside && not (excludedBy policy relative)))
    (throwIO (UnsafeSource "output must be outside the source or explicitly excluded"))
