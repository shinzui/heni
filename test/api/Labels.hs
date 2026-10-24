{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}

-- Compile regression for consumer-defined overloaded labels.
module Labels (labelWorks) where

import GHC.OverloadedLabels (IsLabel (..))
import Test.Heni ()

data ConsumerLabel = ConsumerLabel deriving stock (Eq)

instance IsLabel "consumer" ConsumerLabel where fromLabel = ConsumerLabel

labelWorks :: Bool
labelWorks = #consumer == ConsumerLabel
