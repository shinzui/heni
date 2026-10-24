module Main (main) where

import Control.Monad (unless)
import Subject
import System.Exit (exitFailure)

main :: IO ()
main = do
  unless (not (admits 1 1)) $ do
    putStrLn "rejects full capacity: FAIL"
    exitFailure
  unless (admits 0 1) $ do
    putStrLn "admits spare capacity: FAIL"
    exitFailure
  putStrLn ("capacity assertions: PASS (" ++ marker ++ ")")
