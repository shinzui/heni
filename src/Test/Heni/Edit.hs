-- | Transactional checked edits: the callback sees a candidate only after all
-- preconditions and the independent final inventory have passed.
module Test.Heni.Edit
  ( EditError (..),
    FileChange (..),
    EditEvidence (..),
    PatchRunner,
    withEditedWorkspace,
    workspaceOperations,
  )
where

import Control.Exception
import Control.Monad (forM_, unless, when)
import Data.ByteString qualified as BS
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import System.Directory qualified as Dir
import System.FilePath (splitDirectories, takeDirectory)
import Test.Heni.Case
import Test.Heni.Expectation
import Test.Heni.Internal.Files
import Test.Heni.Workspace

-- | Stale/invalid mutations differ from ordinary filesystem infrastructure errors.
data EditError = InvalidEdit !Text | EditInfrastructure !Text
  deriving stock (Eq, Show)
  deriving anyclass (Exception)

-- | Actual before/after bytes, including creation, deletion and executable modes.
data FileChange = FileChange {path :: !RelativeTarget, before :: !(Maybe FileEntry), after :: !(Maybe FileEntry)}
  deriving stock (Eq, Show)

-- | Independently recomputed changes, not a hook's claimed touched-file list.
newtype EditEvidence = EditEvidence {changes :: [FileChange]}
  deriving stock (Eq, Show)

-- | Inject the common supervisor for optional Git. It must bound and reap children.
-- Arguments are passed literally; the runner supplies its workspace as cwd.
type PatchRunner = FilePath -> [String] -> IO (Either Text ())

-- | Checked trusted-IO capabilities. Writes require existing files; creation and
-- deletion have explicit byte preconditions and reject runner-owned paths.
workspaceOperations :: Workspace -> WorkspaceOps
workspaceOperations workspace = WorkspaceOps readText writeText createText deleteText
  where
    checked target = do
      when (reserved target) (throwIO (InvalidEdit "edit targets runner-owned build/evidence metadata"))
      checkedWorkspacePath workspace target
    readText target = do
      p <- checked target
      b <- BS.readFile p
      either (const (throwIO (InvalidEdit "target is not valid UTF-8"))) pure (Text.decodeUtf8' b)
    writeText target content = do
      _ <- readText target
      p <- checked target
      BS.writeFile p (Text.encodeUtf8 content)
    createText target content = do
      p <- checked target
      exists <- Dir.doesPathExist p
      when exists (throwIO (InvalidEdit "creation target already exists"))
      Dir.createDirectoryIfMissing True (takeDirectory p)
      BS.writeFile p (Text.encodeUtf8 content)
    deleteText target expected = do
      actual <- readText target
      unless (actual == expected) (throwIO (InvalidEdit "deletion precondition failed"))
      p <- checked target
      Dir.removeFile p

reserved :: RelativeTarget -> Bool
reserved target = any (\p -> p `elem` [".git", "dist", "dist-newstyle", ".heni", "mutation-results"] || ".heni-" `Text.isPrefixOf` Text.pack p) (splitDirectories (targetPath target))

-- | Allocate a private candidate, apply ordered edits, inspect all final bytes,
-- then invoke the consumer. Failure or cancellation discards the entire tree.
withEditedWorkspace :: forall a. PatchRunner -> CaseHooks -> SourceSnapshot -> CaseDefinition -> (Workspace -> EditEvidence -> IO a) -> IO (Either EditError a)
withEditedWorkspace runPatch hooks snapshot definition action =
  catches
    (Right <$> withWorkspace snapshot candidate)
    [ Handler (pure . Left :: EditError -> IO (Either EditError a)),
      Handler (\e -> pure (Left (InvalidEdit (Text.pack (show (e :: WorkspaceError)))))),
      Handler (\e -> pure (Left (EditInfrastructure (Text.pack (show (e :: IOException))))))
    ]
  where
    candidate workspace = do
      let CaseDefinition {edits, expectation} = definition
      forM_ edits (apply workspace)
      actual <- inventory (const False) (workspaceRoot workspace)
      let original = snapshotFiles snapshot
          changed =
            [ FileChange p (Map.lookup p original) (Map.lookup p actual)
            | p <- Set.toAscList (Map.keysSet original <> Map.keysSet actual),
              Map.lookup p original /= Map.lookup p actual
            ]
      when (any (\FileChange {path} -> reserved path) changed) (throwIO (InvalidEdit "edit changed runner-owned metadata"))
      when (expectation /= Control && null changed) (throwIO (InvalidEdit "mutation left all bytes unchanged"))
      when (expectation == Control && not (null changed)) (throwIO (InvalidEdit "control changed source bytes"))
      action workspace (EditEvidence changed)
    apply workspace edit = do
      let ops@WorkspaceOps {readTarget, writeTarget, createTarget, deleteTarget} = workspaceOperations workspace
      case edit of
        Replace target old new count -> do
          when (Text.null old || old == new || count <= 0) (throwIO (InvalidEdit "invalid replacement definition"))
          actual <- readTarget target
          unless (Text.count old actual == count) (throwIO (InvalidEdit "replacement anchor count did not match"))
          writeTarget target (Text.replace old new actual)
        Create target content -> createTarget target content
        Delete target expected -> deleteTarget target expected
        CustomEdit key -> case hooks of
          CaseHooks {customEdits} -> case lookup key customEdits of
            Nothing -> throwIO (InvalidEdit ("missing custom edit hook: " <> key))
            Just hook -> hook ops
        Patch content -> do
          targets <- either (throwIO . InvalidEdit) pure (patchTargets content)
          mapM_ (checkedWorkspacePath workspace) targets
          withOwnedDirectory ".heni-patch-" $ \scratch -> do
            let patchFile = scratch ++ "/candidate.patch"
            BS.writeFile patchFile (Text.encodeUtf8 content)
            forM_ [["apply", "--check", "--", patchFile], ["apply", "--", patchFile]] $ \args -> do
              result <- runPatch (workspaceRoot workspace) args
              either (throwIO . InvalidEdit) pure result

patchTargets :: Text -> Either Text [RelativeTarget]
patchTargets content
  | any unsupported lines' = Left "only textual Git patches without rename/copy/mode/binary operations are supported"
  | null headers = Left "patch requires diff --git headers"
  | otherwise = do
      diffs <- concat <$> mapM parse headers
      paths <- mapM parseFileHeader (filter (\line -> "--- " `Text.isPrefixOf` line || "+++ " `Text.isPrefixOf` line) lines')
      let allPaths = diffs ++ [p | Just p <- paths]
      if any reserved allPaths then Left "patch targets runner-owned metadata" else Right allPaths
  where
    lines' = Text.lines content
    headers = filter (Text.isPrefixOf "diff --git ") lines'
    unsupported line =
      any
        (`Text.isPrefixOf` line)
        ["GIT binary patch", "Binary files ", "rename ", "copy ", "old mode ", "new mode "]
        || ("new file mode " `Text.isPrefixOf` line && line `notElem` ["new file mode 100644", "new file mode 100755"])
        || ("deleted file mode " `Text.isPrefixOf` line && line `notElem` ["deleted file mode 100644", "deleted file mode 100755"])
        || ("index " `Text.isPrefixOf` line && "120000" `Text.isSuffixOf` line)
    parse line = case Text.words line of
      ["diff", "--git", a, b] -> do
        x <- pathAfter "a/" a
        y <- pathAfter "b/" b
        if x /= y then Left "patch renaming is unsupported" else Right [x, y]
      _ -> Left "quoted or spaced patch paths are not supported"
    pathAfter prefix t = case Text.stripPrefix prefix t of
      Nothing -> Left "patch requires a/ and b/ paths"
      Just p -> either (Left . Text.pack . show) Right (mkRelativeTarget (Text.unpack p))
    parseFileHeader line
      | Text.drop 4 line == "/dev/null" = Right Nothing
      | "--- " `Text.isPrefixOf` line = Just <$> pathAfter "a/" (Text.drop 4 line)
      | otherwise = Just <$> pathAfter "b/" (Text.drop 4 line)
