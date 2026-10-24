-- | Deliberate mutation definitions and trustworthy evidence classification.
--
-- Construct and validate a 'CaseDefinition', collect evidence, then call
-- 'classifyCase'. The execution runner is added by the campaign implementation;
-- this module never prints output or terminates the embedding application.
module Test.Heni
  ( module Test.Heni.Case,
    module Test.Heni.Command,
    module Test.Heni.Expectation,
    module Test.Heni.Result,
    module Test.Heni.Runner,
    module Test.Heni.Report,
  )
where

import Test.Heni.Case
import Test.Heni.Command
import Test.Heni.Expectation
import Test.Heni.Report
import Test.Heni.Result
import Test.Heni.Runner
