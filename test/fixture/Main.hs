module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Monad (forever, replicateM_)
import Data.ByteString qualified as BS
import Data.List (isInfixOf)
import System.Environment (getArgs, getExecutablePath)
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
