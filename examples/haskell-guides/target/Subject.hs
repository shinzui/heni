module Subject (admits, marker) where

admits :: Int -> Int -> Bool
admits used limit = used < limit

marker :: String
marker = "baseline"
