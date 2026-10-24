module Main (main) where

import Data.List (isInfixOf)
import System.Directory (createDirectoryIfMissing)
import System.Exit (exitWith)
import System.IO (hFlush, stdout)
import System.Process (rawSystem)

main :: IO ()
main = do
  model <- readFile "model.txt"
  let guard = if "mode=strict" `isInfixOf` model then "used < limit" else "True"
      generated = "module Generated (admits) where\nadmits :: Int -> Int -> Bool\nadmits used limit = " ++ guard ++ "\n"
  createDirectoryIfMissing True "generated"
  writeFile "generated/Generated.hs" generated
  putStrLn ("compiled generator input: " ++ show model ++ "; artifact: admits used limit = " ++ guard)
  hFlush stdout
  rawSystem "cabal" ["build", "fixture-test", "--offline", "-j1"] >>= exitWith
