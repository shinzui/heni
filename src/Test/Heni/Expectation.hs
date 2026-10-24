-- | Explicit expectation and selection evidence. Framework types never enter the core.
module Test.Heni.Expectation
  ( Expectation (..),
    ReplayPolicy (..),
    ReplayEvidence (..),
    SelectionEvidence (..),
    unknownSelection,
    StageEvidence (..),
  )
where

import Test.Heni.Internal.Model
