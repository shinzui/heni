-- | Fresh attempt-bound reachability probes for explicitly expected native signals.
module Test.Heni.Crash (recordCrashProbe, writeCrashProbe, readCrashProbe, probeRelativePath) where

import Control.Exception
import Control.Monad (forM_, unless, when)
import Data.Aeson
import Data.Aeson.KeyMap qualified as KM
import Data.Aeson.Types (parseEither)
import Data.ByteString qualified as BS
import Data.ByteString.Lazy qualified as LBS
import Data.Text (Text)
import Data.Text qualified as Text
import System.Directory qualified as Dir
import System.FilePath ((</>))
import System.IO
import Test.Heni.Adapter
import Test.Heni.Case (mkRelativeTarget)
import Test.Heni.Internal.Codec (decodeJSON, strictObject)
import Test.Heni.Internal.Files (WorkspaceError, checkedPath)

-- | Relative path kept with the report's other artifacts.
probeRelativePath :: EvidenceAttempt -> FilePath
probeRelativePath EvidenceAttempt {directoryName} = directoryName </> "probe.json"

-- | Called immediately before the intended native operation. Outside Heni it is
-- a no-op; under Heni it refuses to replace existing probe evidence.
recordCrashProbe :: Text -> IO ()
recordCrashProbe probe = currentEvidenceAttempt >>= mapM_ (`writeCrashProbe` probe)

-- | Explicit form for non-environment integrations and conformance fixtures.
writeCrashProbe :: EvidenceAttempt -> Text -> IO ()
writeCrashProbe attempt@EvidenceAttempt {outputRoot} probe = do
  when (Text.null probe || Text.length probe > 65536) (throwIO (EvidenceError "probe must be nonempty and bounded"))
  let path = outputRoot </> probeRelativePath attempt
  exists <- Dir.doesPathExist path
  when exists (throwIO (EvidenceError "probe destination already exists"))
  case attemptIdentityJSON attempt of
    Object identity -> withBinaryFile path WriteMode $ \file -> LBS.hPut file (encode (Object (KM.insert "probe" (String probe) identity))) >> hFlush file
    _ -> error "attempt identity object"

-- | Missing, stale or mismatched probes never prove reachability. The caller
-- retains the rejection reason alongside the actual exit/signal evidence.
readCrashProbe :: EvidenceAttempt -> Text -> IO (Either Text ())
readCrashProbe attempt@EvidenceAttempt {outputRoot} expected =
  catches
    (Right <$> action)
    [ Handler (\(EvidenceError why) -> pure (Left why)),
      Handler (\(e :: IOException) -> pure (Left (Text.pack (show e)))),
      Handler (\(e :: WorkspaceError) -> pure (Left (Text.pack (show e))))
    ]
  where
    action = do
      target <- either (throwIO . EvidenceError . Text.pack . show) pure (mkRelativeTarget (probeRelativePath attempt))
      path <- checkedPath outputRoot target
      bytes <- withBinaryFile path ReadMode (\file -> BS.hGet file 262145)
      when (BS.length bytes > 262144) (throwIO (EvidenceError "probe exceeds size limit"))
      value <- either (throwIO . EvidenceError . Text.pack) pure (decodeJSON bytes)
      identity <- case attemptIdentityJSON attempt of
        Object fields -> pure fields
        _ -> throwIO (EvidenceError "internal attempt identity is not an object")
      either
        (throwIO . EvidenceError . Text.pack)
        pure
        ( parseEither
            ( strictObject "crash probe" ("probe" : KM.keys identity) $ \o -> do
                forM_ (KM.toList identity) $ \(key, wanted) -> unless (KM.lookup key o == Just wanted) (fail "stale or wrong crash probe attempt identity")
                probe <- o .: "probe"
                unless (probe == expected) (fail "wrong crash reachability probe")
            )
            value
        )
