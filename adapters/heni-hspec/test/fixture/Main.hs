module Main (main) where

import System.Environment (getArgs)
import Test.Heni.Hspec
import Test.Hspec
import Test.QuickCheck qualified as QC

main :: IO ()
main =
  getArgs >>= \case
    ["--heni-build"] -> pure ()
    _ -> do
      mode <- readFile "input"
      heniHspec $ describe "suite" $ do
        it "intended" $ if mode == "skipped" then pending else mode `shouldNotBe` "intended"
        it "other" $ if mode == "setup" then ioError (userError "fixture setup failed") else mode `shouldNotBe` "wrong"
        it "property" $
          heniProperty "suite/property" (QC.stdArgs {QC.maxSuccess = 1, QC.maxSize = 30}) $
            QC.forAll (QC.chooseInt (1, 100)) (\n -> mode /= "property" || n < 0)
