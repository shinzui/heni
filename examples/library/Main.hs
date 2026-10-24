module Main (main) where

import Definitions (exampleCampaign)
import System.Environment (getArgs)
import Test.Heni

main :: IO ()
main = do
  args <- getArgs
  let output = case args of ["--output", path] -> path; _ -> ".heni-runs/library-smoke"
  result <- runCampaign (defaultRunOptions "examples/minimal" output) exampleCampaign
  print result
