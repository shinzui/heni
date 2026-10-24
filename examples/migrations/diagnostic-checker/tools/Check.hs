module Main (main) where

import Data.List (isInfixOf)
import System.Exit (ExitCode (..), exitWith)

main :: IO ()
main = do
  input <- readFile "policy.txt"
  if "capacity=-1" `isInfixOf` input
    then reject "policy.capacity: maximum must be positive"
    else
      if "timeout=-1" `isInfixOf` input
        then reject "policy.timeout: duration must be positive"
        else putStrLn "policy: PASS"
  where
    reject why = putStrLn why >> exitWith (ExitFailure 1)
