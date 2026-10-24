module Main (main) where

import System.Directory (createDirectoryIfMissing)
import System.Exit (exitWith)
import System.Process (rawSystem)

main :: IO ()
main = do
  createDirectoryIfMissing True "dist-newstyle"
  rawSystem "ghc" ["-O0", "-outputdir", "dist-newstyle", "-o", "dist-newstyle/checker", "tools/Check.hs"] >>= exitWith
