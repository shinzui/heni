module GuideManifest (runManifest) where

import Control.Monad (unless)
import GuideSupport (expectVerdicts)
import System.FilePath ((</>))
import Test.Heni qualified as H

runManifest :: FilePath -> FilePath -> IO ()
runManifest source output = do
  decoded <- H.readManifest (source </> "heni.json")
  manifest <- either (ioError . userError . show) pure decoded
  applicable <- H.checkManifest manifest >>= either (ioError . userError . show) pure
  unless (all (\H.Applicability {H.applicable = good} -> good) applicable) (error (show applicable))
  -- Neither readManifest nor checkManifest runs builds or tests. The runner does.
  result <- H.runCampaign (H.manifestRunOptions output manifest) (H.manifestCampaign manifest)
  expectVerdicts [H.Caught] result
