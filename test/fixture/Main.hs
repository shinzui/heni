module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Monad (forever, replicateM_)
import Data.ByteString qualified as BS
import Data.List (isInfixOf)
import System.Directory qualified as Dir
import System.Environment (getArgs, getExecutablePath, lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.IO
import System.IO.Error (catchIOError)
import System.Posix.Process (createSession, getProcessID)
import System.Posix.Signals
import System.Process qualified as P

main :: IO ()
main = do
  hSetBuffering stdout NoBuffering
  hSetBuffering stderr NoBuffering
  getArgs >>= \case
    ["exit", code] -> exitWith (if code == "0" then ExitSuccess else ExitFailure (read code))
    ["signal"] -> getProcessID >>= signalProcess sigABRT
    ["sleep"] -> putStrLn "exact-witness" >> threadDelay 30000000
    ["ignore", marker] -> do
      _ <- installHandler sigTERM Ignore Nothing
      pid <- getProcessID
      writeFile marker (show pid)
      forever (threadDelay 1000000)
    ["descendant", marker] -> do
      exe <- getExecutablePath
      _ <- P.createProcess (P.proc exe ["ignore", marker])
      waitForMarker marker
      -- Exit while the descendant retains stdout/stderr and ignores SIGTERM.
      pure ()
    ["detached", marker] -> do
      _ <- createSession
      pid <- getProcessID
      writeFile marker (show pid)
      forever (threadDelay 1000000)
    ["detach", marker] -> do
      exe <- getExecutablePath
      _ <- P.createProcess (P.proc exe ["detached", marker])
      waitForMarker marker
    ["flood"] -> do
      replicateM_ 200 (BS.hPut stdout (BS.replicate 32768 65) >> BS.hPut stderr (BS.replicate 32768 66))
      BS.hPut stdout "exact-"
      threadDelay 10000
      BS.hPut stdout "witness"
      exitWith (ExitFailure 1)
    ["invalid-utf8"] -> BS.hPut stdout (BS.pack [255]) >> exitWith (ExitFailure 1)
    ["incremental-build", mode] -> do
      content <- readFile "input"
      key <- maybe "fresh" id <$> lookupEnv "HENI_BUILD_INPUT_ID"
      Dir.createDirectoryIfMissing True "dist-newstyle"
      exists <- Dir.doesFileExist "dist-newstyle/observed-key"
      old <- if exists then readFile "dist-newstyle/observed-key" else pure "absent"
      length old `seq` pure ()
      if (mode == "unsafe" && exists) || old == key
        then pure ()
        else do
          writeFile "dist-newstyle/compiled" content
          writeFile "dist-newstyle/observed-key" key
      if mode == "generated" then writeFile "unexpected-generated" "unexpected" else pure ()
      if mode == "reject" && content == "mutant" then putStrLn "intended-build-rejection" >> exitWith (ExitFailure 1) else pure ()
    ["incremental-test"] -> do
      compiled <- readFile "dist-newstyle/compiled"
      if compiled == "mutant" then putStrLn "capacity rule violated" >> exitWith (ExitFailure 1) else pure ()
    ["counter", path] -> do
      previous <- readFile path `catchIOError` const (pure "0")
      let n = (read previous :: Int) + 1
      length previous `seq` writeFile path (show n)
      if n > 1 then putStrLn "unchanged control failed" >> exitWith (ExitFailure 1) else pure ()
    ["check", path, mode] -> do
      content <- readFile path
      if "mutant" `isInfixOf` content
        then case mode of
          "diagnostic" -> putStrLn "capacity rule violated" >> exitWith (ExitFailure 1)
          "wrong" -> putStrLn "unrelated failure" >> exitWith (ExitFailure 1)
          "timeout" -> putStrLn "capacity rule violated" >> threadDelay 30000000
          _ -> pure ()
        else pure ()
    ["check", path, "timeout", marker] -> do
      content <- readFile path
      if "mutant" `isInfixOf` content
        then do
          pid <- getProcessID
          writeFile marker (show pid)
          putStrLn "capacity rule violated"
          threadDelay 30000000
        else pure ()
    "echo" : args -> mapM_ print args
    _ -> error "unknown fixture mode"

waitForMarker :: FilePath -> IO ()
waitForMarker marker = do
  ready <- (not . null) <$> (readFile marker `catchIOError` const (pure ""))
  if ready then pure () else threadDelay 5000 >> waitForMarker marker
