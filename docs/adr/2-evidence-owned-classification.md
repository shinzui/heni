# Evidence owns the verdict

Status: accepted. Date: 2026-10-24.

Every execution path calls the same pure classifyCase and summarizeRun.
Expectations cannot override process outcomes, baseline success, changed-byte
requirements, setup, timeout or cleanup validity. Evidence is distinct from a
verdict and retains secondary failures. Generic diagnostics disclose their
weaker attribution instead of inventing framework test counts.

Named detection requires the exact declared assertion failure set and actual
execution. Required replay carries the same token, generator and failure
identity. Explicit crash probes and intentional build rejections are distinct
from semantic kills. Timeouts remain unresolved. Unchanged controls are the
only permitted no-op cases and invalidate run confidence when they fail.

A validated selection ledger owns exactly-once accounting; missing results are
NotRun, and duplicate/foreign evidence is rejected. Infrastructure takes
precedence over survivors in run status. The semantic fraction excludes
controls, crashes, build rejection and unresolved outcomes, and is marked
incomplete when any run obligation remains. This conservatism prevents ordinary
command errors from turning a broken mutation campaign green.

The executable truth table and ledger invariants live in test/unit/Main.hs;
the detailed precedence contract is in docs/user/classification.md.
