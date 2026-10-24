# Source archives define the release validation boundary

Status: accepted. Date: 2026-10-24.

Validate the four Heni source distributions outside the checkout, with released
non-Heni dependencies. A core-only project must work independently; inspect the
reachable component graph rather than every node in Cabal's elaborated plan.
Aeson brings transitive QuickCheck, while Tasty/Hspec and Heni reporters remain
optional. Keep framework test APIs outside the core.

Run core tests with a restricted tool path, then separately require positive Git
patch integration and optional framework reporters. Archive tests also prove
complete Haddock, schema agreement, the standalone library/CLI exit contract and
representative migrations. Preserve failed extractions and bounded validation
logs. Do not let absence of a capability silently satisfy its positive gate.

Advertise only successfully tested OS/compiler combinations and dependency sets.
GHC 9.12.4 is both ends of the initial admitted compiler range; widening base
bounds is a compatibility task. Keep -Werror in owned CI policy. Version public
Haskell APIs under PVP independently from wire schemas.

The maintainer selected BSD-3-Clause and supplied metadata by reference to their
other packages. Name lookups are neither reservations nor ownership checks.
Source/docs hashes and readiness evidence are repository-only records excluded
from source distributions to avoid self-reference. Candidate upload, rendered
Hackage review, account authorization and publication remain separate release
actions after local readiness; local artifacts never imply an upload occurred.
