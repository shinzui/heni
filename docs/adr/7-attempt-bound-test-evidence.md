# Attempt-bound test evidence and replay

Status: accepted. Date: 2026-10-24.

Framework adapters describe observations through a dedicated versioned JSON
Lines artifact. Only the core classifier chooses verdicts. Bind every record
to a fresh run/case/stage/role/attempt identity and cross-check completion,
counts, test transitions and failure membership. Reject stale, malformed and
partial evidence without falling back to diagnostic matching. A framework
exception after completion appends explicit invalidation while retaining facts.

Stable escaped path IDs distinguish nested or parameterized display names.
Unknown unfiltered discovery remains unknown. Report selected/executed IDs
exactly and require intended assertions to execute in both baseline and
candidate. Optional framework packages own version-specific public APIs;
framework types never enter the core public import closure.

Required replay is a supervised second attempt in the same edited workspace.
Preserve both observations and exact framework token/configuration. A replay
timeout is a failed reproduction, with the underlying Timeout retained, not
a semantic detection. Support one explicit QuickCheck replay property per
selected attempt initially; use typed builders for other native protocols.

A declared crash needs a fresh attempt-bound reachability probe and actual
native signal, with no timeout/cancellation. Probes do not prove arbitrary
root cause. These artifacts assume cooperating test programs and do not
provide cryptographic attestation against them.
