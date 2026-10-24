-- | Owned temporary paths and checked byte inventories. POSIX first release.
module Test.Heni.Internal.Files where

import Control.Exception
import Control.Monad (forM, forM_, unless, when)
import Crypto.Hash (Digest, SHA256, hash)
import Data.Bits ((.&.))
import Data.ByteString qualified as BS
import Data.ByteString.Char8 qualified as B8
import Data.List (sort)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import System.Directory qualified as Dir
import System.FilePath (takeDirectory, (</>))
import System.IO.Error (isDoesNotExistError)
import System.Posix.Files qualified as Posix
import System.Posix.Temp (mkdtemp)
import Test.Heni.Case (RelativeTarget, mkRelativeTarget, targetPath)

-- | Structured filesystem failure; ordinary IO errors remain IOException.
data WorkspaceError = UnsafeSource !Text | SourceChanged | WorkspaceMismatch !Text
  deriving stock (Eq, Show)
  deriving anyclass (Exception)

-- | Immutable bytes and executable bits, excluding ownership and timestamps.
data FileEntry = FileEntry {bytes :: !BS.ByteString, executableBits :: !Int}
  deriving stock (Eq, Show)

type Inventory = Map.Map RelativeTarget FileEntry

digest :: BS.ByteString -> Text
digest = Text.pack . show . (hash :: BS.ByteString -> Digest SHA256)

framed :: BS.ByteString -> BS.ByteString
framed b = B8.pack (show (BS.length b) ++ ":") <> b

inventoryDigest :: Text -> Inventory -> Text
inventoryDigest policy files =
  digest $
    framed (Text.encodeUtf8 policy)
      <> BS.concat [framed (Text.encodeUtf8 (Text.pack (targetPath p))) <> framed (B8.pack (show mode)) <> framed b | (p, FileEntry b mode) <- Map.toAscList files]

withOwnedDirectory :: String -> (FilePath -> IO a) -> IO a
withOwnedDirectory prefix action = bracket allocate Dir.removePathForcibly action
  where
    allocate = do
      temp <- Dir.getTemporaryDirectory >>= Dir.canonicalizePath
      mkdtemp (temp </> prefix)

-- | No symlink component is accepted, including a dangling link. Call before IO.
checkedPath :: FilePath -> RelativeTarget -> IO FilePath
checkedPath root target = do
  rootStatus <- Posix.getSymbolicLinkStatus root
  unless (Posix.isDirectory rootStatus && not (Posix.isSymbolicLink rootStatus)) (throwIO (UnsafeSource "workspace root is not a directory"))
  go root (Text.splitOn "/" (Text.pack (targetPath target)))
  pure (root </> targetPath target)
  where
    go _ [] = pure ()
    go current (part : rest) = do
      let p = current </> Text.unpack part
      status <- tryIO (Posix.getSymbolicLinkStatus p)
      case status of
        Left e | isDoesNotExistError e -> pure ()
        Left e -> throwIO e
        Right st -> do
          when (Posix.isSymbolicLink st) (throwIO (UnsafeSource ("symlink target: " <> Text.pack p)))
          unless
            (if null rest then Posix.isRegularFile st || Posix.isDirectory st else Posix.isDirectory st)
            (throwIO (UnsafeSource ("non-regular path: " <> Text.pack p)))
          go p rest

tryIO :: IO a -> IO (Either IOException a)
tryIO = try

-- | Read the exact selected regular-file tree; names are canonical relative paths.
inventory :: (FilePath -> Bool) -> FilePath -> IO Inventory
inventory excluded root = Map.fromList <$> walk ""
  where
    walk relative = do
      let full = if null relative then root else root </> relative
      st <- Posix.getSymbolicLinkStatus full
      when (Posix.isSymbolicLink st) (throwIO (UnsafeSource ("source symlink is unsupported: " <> Text.pack relative)))
      if Posix.isDirectory st
        then do
          names <- sort <$> Dir.listDirectory full
          concat <$> forM names (\n -> let p = if null relative then n else relative </> n in if excluded p then pure [] else walk p)
        else
          if Posix.isRegularFile st
            then do
              target <- either (throwIO . UnsafeSource . Text.pack . show) pure (mkRelativeTarget relative)
              b <- BS.readFile full
              pure [(target, FileEntry b (fromIntegral (Posix.fileMode st .&. 0o111)))]
            else throwIO (UnsafeSource ("special source file is unsupported: " <> Text.pack relative))

materialize :: FilePath -> Inventory -> IO ()
materialize root files = forM_ (Map.toAscList files) $ \(target, FileEntry b mode) -> do
  p <- checkedPath root target
  Dir.createDirectoryIfMissing True (takeDirectory p)
  BS.writeFile p b
  Posix.setFileMode p (0o600 + fromIntegral mode)
