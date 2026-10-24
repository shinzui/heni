module Main (main) where

import System.Environment (getArgs)
import Test.Heni.Tasty
import Test.Tasty
import Test.Tasty.HUnit

main :: IO ()
main =
  getArgs >>= \case
    ["--heni-build"] -> pure ()
    _ -> do
      mode <- readFile "input"
      heniMain $
        testGroup
          "suite"
          [ testCase "intended" (assertBool "intended assertion" (mode /= "intended")),
            testCase "other" (if mode == "setup" then ioError (userError "fixture setup failed") else assertBool "other assertion" (mode /= "wrong"))
          ]
