module Capacity (admits, marker) where

admits :: Int -> Int -> Bool
admits used limit = used < limit

marker :: String
marker = "baseline"
