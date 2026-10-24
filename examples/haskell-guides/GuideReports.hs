module GuideReports (gateExit, printResult, inspectReport) where

import Control.Monad (unless)
import Data.Aeson (encode)
import Data.ByteString.Lazy.Char8 qualified as LBS
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory)
import Test.Heni qualified as H

gateExit :: H.RunResult -> ExitCode
gateExit H.RunResult {H.status} = case status of
  H.RunPassed -> ExitSuccess
  H.RunFailed -> ExitFailure 1
  H.RunUntrustworthy -> ExitFailure 2
  H.RunInterrupted -> ExitFailure 130

printResult :: H.RunResult -> IO ()
printResult result@H.RunResult {H.results, H.failures, H.score} = do
  putStrLn ("Campaign gate: " ++ show (gateExit result))
  mapM_
    ( \H.CaseResult {H.caseId, H.verdict, H.detection, H.reason, H.evidence = H.CaseEvidence {H.stages}} -> do
        print (H.caseIdText caseId, verdict, detection, reason)
        mapM_
          (\H.StageEvidence {H.stage, H.outcome, H.selection, H.replay, H.logPaths} -> print (stage, outcome, selection, replay, logPaths))
          stages
    )
    results
  mapM_ print failures
  case score of
    Nothing -> putStrLn "No semantic caught/survived denominator."
    Just (H.SemanticScore caught total complete) -> print (caught, total, complete)
  -- Export through the explicit wire codec, never by deriving from constructors.
  LBS.putStrLn (encode (H.runResultJSON result))

inspectReport :: FilePath -> IO ()
inspectReport path = do
  loaded <- H.readReport path
  case loaded of
    Left err -> ioError (userError ("Report could not be validated: " ++ show err))
    Right stored@H.StoredReport {H.result} -> do
      printResult result
      LBS.putStrLn (encode (H.reportJSON stored))
  recovered <- H.recoverReport (takeDirectory path)
  case recovered of
    Left err -> ioError (userError ("Journal could not be recovered: " ++ show err))
    Right H.StoredReport {H.result = result@H.RunResult {H.status}} -> do
      unless (status == H.RunUntrustworthy) (error "recovery incorrectly claimed trust")
      putStrLn ("Recovered gate: " ++ show (gateExit result))
