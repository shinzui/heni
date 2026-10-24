# Framework-neutral public library

Status: accepted. Date: 2026-10-24.

Heni owns definitions, checked execution, evidence classification and reports.
The CLI wraps those library APIs. Optional test frameworks supply evidence in
separate packages and never export their types through Test.Heni. Consumers own
service fixtures and effects, discharged into plain IO hooks. Portable case
data and executable hooks remain separate; arbitrary functions are not JSON.

Use strict concrete records, GHC2024 and a small internal prelude. Constructor
matching and explicit combinators keep generic-lens's transitive label orphan
out of the public import closure. This is a scoped adaptation of
mori://shinzui/haskell-jitsurei/docs/core-record-patterns. A downstream compile
fixture defines its own IsLabel instance while importing Test.Heni.

This boundary keeps ordinary Cabal consumers independent of application effect
stacks, Mori, OKF, Nix and test-framework dependencies. The cost is separate
optional packages and explicit codecs. It follows the boundary lessons of
mori://shinzui/mori-app/okf/adrs/concepts/ADR-1 and
mori://shinzui/keiro/okf/adrs/concepts/ADR-28 without adopting their frameworks.
