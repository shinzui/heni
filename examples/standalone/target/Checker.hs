module Main (main) where

import System.Exit (exitFailure)

main :: IO ()
main = do
  input <- readFile "input"
  case input of
    "mutant\n" -> putStrLn "capacity rule violated" >> exitFailure
    "unrelated\n" -> putStrLn "unrelated checker failure" >> exitFailure
    _ -> pure ()
