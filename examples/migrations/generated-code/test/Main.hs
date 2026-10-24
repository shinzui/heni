module Main (main) where

import Generated
import System.Exit (exitFailure)

main :: IO ()
main = if not (admits 10 10) then putStrLn "generated capacity: PASS" else putStrLn "generated capacity: FAIL" >> exitFailure
