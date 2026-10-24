{-# LANGUAGE RankNTypes #-}

-- | Consumer-owned resource lifetimes. Trusted callbacks must implement their
-- own external reset semantics; workspace disposal cannot roll back a service.
module Test.Heni.Resource
  ( ResourceScope (..),
    ResourceBinding (..),
    ResourceContext (..),
    ResourceEvent (..),
    ResourceProvider,
    resourceName,
    resourceScope,
    resourceCapacity,
    resourceCommands,
    ResourceLease,
    resourceBinding,
    prepareResource,
    managedResource,
    commandResource,
    withResources,
    validateResources,
    ResourcePhase (..),
    ResourceError (..),
    bindingEnvironment,
  )
where

import Control.Exception
import Control.Monad (unless)
import Data.Char (isAsciiUpper)
import Data.IORef
import Data.List (nub)
import Data.Text (Text)
import Data.Text qualified as Text
import Test.Heni.Case (ConfigError (..))
import Test.Heni.Command
import Test.Heni.Expectation
import Test.Heni.Internal.Files (withFinalizer)
import Test.Heni.Process
import Test.Heni.Workspace

-- | One acquisition for the campaign, each worker, or each claimed case.
data ResourceScope = CampaignScope | WorkerScope | CaseScope deriving stock (Eq, Show)

-- | Nonsecret identities/versions are reportable. Unknown epoch disables reuse;
-- environment values remain in memory and are redacted from portable reports.
data ResourceBinding = ResourceBinding
  {identity :: !Text, version :: !Text, epoch :: !(Maybe Text), environment :: ![(String, String)]}
  deriving stock (Eq, Show)

-- | Owned context for resource hooks and their supervised command artifacts.
data ResourceContext = ResourceContext
  { instanceId :: !Text,
    snapshot :: !SourceSnapshot,
    artifactDirectory :: !FilePath,
    observeResource :: !(ResourceEvent -> IO ())
  }

-- | Facts about completed ownership transitions, with no environment values.
data ResourceEvent = ResourceEvent !Text !Text !ResourcePhase !ResourceBinding | ResourceCommandFinished !Text !Text !ResourcePhase !ProcessReport
  deriving stock (Eq, Show)

-- | Lifecycle failures differ from test assertions.
data ResourcePhase = AcquireResource | ResetResource | ReleaseResource deriving stock (Eq, Show)

-- | Resource name, failed lifecycle phase and original exception.
data ResourceError = ResourceError !Text !ResourcePhase !SomeException
  deriving stock (Show)
  deriving anyclass (Exception)

-- | Opaque lease; only its owner can update the prepared state.
data ResourceLease = ResourceLease !(IO ResourceBinding) !(IO ResourceBinding)

-- | A scoped CPS provider keeps arbitrary consumer values out of JSON/core types.
data ResourceProvider = ResourceProvider
  { -- | Uppercase identity used by claims and environment namespaces.
    resourceName :: !Text,
    -- | Ownership lifetime; each instance is acquired and released once.
    resourceScope :: !ResourceScope,
    -- | Maximum concurrent claims, also bounding worker-scoped acquisition.
    resourceCapacity :: !Int,
    -- | Portable lifecycle commands for preflight; arbitrary providers use [].
    resourceCommands :: ![Command],
    provide :: forall a. ResourceContext -> (ResourceLease -> IO a) -> IO a
  }

-- | Current identity without changing the external fixture.
resourceBinding :: ResourceLease -> IO ResourceBinding
resourceBinding (ResourceLease current _) = current

-- | Reset before both baseline and candidate; a failure invalidates the case.
prepareResource :: ResourceLease -> IO ResourceBinding
prepareResource (ResourceLease _ reset) = reset

-- | Acquire in declaration order and release in reverse order, including partial
-- acquisition, callback failure and cancellation. Cleanup failures retain the
-- primary exception via 'WorkspaceFinalizationError'. No timeout guarantee is
-- possible for arbitrary uninterruptible consumer foreign calls.
managedResource :: Text -> ResourceScope -> Int -> (ResourceContext -> IO (value, ResourceBinding)) -> (value -> IO ResourceBinding) -> (value -> IO ()) -> ResourceProvider
managedResource name scope capacity acquire reset release = ResourceProvider name scope capacity [] $ \context@ResourceContext {instanceId, observeResource} action -> mask $ \restore -> do
  (value, initial) <- phase AcquireResource (restore (acquire context))
  current <- newIORef initial
  let announce p b = observeResource (ResourceEvent name instanceId p b)
      check b = either (throwIO . userError . show) pure (validateBinding name b)
      resetLease = mask $ \unmask -> do
        next <- phase ResetResource (unmask (reset value))
        writeIORef current next
        check next
        announce ResetResource next
        pure next
      dispose = do
        latest <- readIORef current
        phase ReleaseResource (release value)
        announce ReleaseResource latest
  (check initial >> announce AcquireResource initial >> restore (action (ResourceLease (readIORef current) resetLease))) `withFinalizer` dispose
  where
    phase :: ResourcePhase -> IO b -> IO b
    phase step work =
      work `catch` \(e :: SomeException) -> case fromException e :: Maybe SomeAsyncException of
        Just _ -> throwIO e
        Nothing -> throwIO (ResourceError name step e)

-- | Portable supervised setup/reset/teardown. Each provider instance owns a
-- private workspace. Commands have independent declared budgets and logs.
commandResource :: Text -> ResourceScope -> Int -> ResourceBinding -> Command -> Command -> Command -> ResourceProvider
commandResource name scope capacity binding setup reset teardown = ResourceProvider name scope capacity [setup, reset, teardown] $ \context@ResourceContext {snapshot, artifactDirectory, instanceId, observeResource} action ->
  withWorkspace snapshot $ \workspace -> do
    counter <- newIORef (0 :: Int)
    let run phase command = do
          index <- atomicModifyIORef' counter (\n -> (n + 1, n))
          let prefix = "resource-" ++ Text.unpack name ++ "-" ++ Text.unpack instanceId ++ "-" ++ show index
          report@ProcessReport {evidence = StageEvidence {outcome}, errors} <-
            runCommand (defaultProcessOptions artifactDirectory prefix) workspace (if phase == ReleaseResource then Teardown else Setup) (addEnvironment command)
              `catch` \ProcessAborted {report, cause} -> throwIO cause `withFinalizer` observeResource (ResourceCommandFinished name instanceId phase report)
          observeResource (ResourceCommandFinished name instanceId phase report)
          unless (outcome == Exited 0 && null errors) (ioError (userError ("resource command " ++ show phase ++ ": " ++ show outcome ++ " " ++ show errors)))
        addEnvironment (Command e a s w env b o) = Command e a s w (environment ++ filter ((`notElem` map fst environment) . fst) env) b o
        ResourceBinding {environment} = binding
        provider = managedResource name scope capacity (\_ -> run AcquireResource setup >> pure ((), binding)) (\() -> run ResetResource reset >> pure binding) (\() -> run ReleaseResource teardown)
    provide provider context action

-- | Compose ownership; the callback receives named opaque leases.
withResources :: [ResourceProvider] -> ResourceContext -> ([(Text, ResourceLease)] -> IO a) -> IO a
withResources [] _ action = action []
withResources (provider : rest) context action = provide provider context $ \lease ->
  withResources rest context (action . ((resourceName provider, lease) :))

-- | Validate names, capacities and namespaces before any acquisition.
validateResources :: [ResourceProvider] -> Either ConfigError ()
validateResources providers = do
  let names = map resourceName providers
  unless (length names == length (nub names)) (Left (ConfigError "resources" "duplicate resource name"))
  mapM_
    ( \ResourceProvider {resourceName, resourceCapacity} -> do
        unless (validName resourceName) (Left (ConfigError "resources.name" "use uppercase ASCII names with digits/underscores"))
        unless (resourceCapacity > 0) (Left (ConfigError "resources.capacity" "capacity must be positive"))
    )
    providers

validName :: Text -> Bool
validName name = case Text.uncons name of Nothing -> False; Just (first, rest) -> isAsciiUpper first && Text.all (\c -> isAsciiUpper c || (c >= '0' && c <= '9') || c == '_') rest

validateBinding :: Text -> ResourceBinding -> Either ConfigError ()
validateBinding name ResourceBinding {identity, version, epoch, environment} = do
  unless (not (Text.null identity || Text.null version) && maybe True (not . Text.null) epoch) (Left (ConfigError "resource.binding" "identity/version/known epoch must be nonempty"))
  let keys = map fst environment
      prefix = "HENI_RESOURCE_" <> name <> "_"
  unless (length keys == length (nub keys) && all (\key -> prefix `Text.isPrefixOf` Text.pack key && not (any (`elem` ['=', '\0']) key)) keys && all (notElem '\0' . snd) environment) (Left (ConfigError "resource.environment" "duplicate or unnamespaced environment binding"))

-- | Combine bindings only after validation; resource namespaces prevent clashes.
bindingEnvironment :: [(Text, ResourceBinding)] -> Either ConfigError [(String, String)]
bindingEnvironment bindings = mapM_ (uncurry validateBinding) bindings >> pure (concatMap (\(_, ResourceBinding {environment}) -> environment) bindings)
