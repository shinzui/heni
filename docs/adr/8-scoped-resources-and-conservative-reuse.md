# Scoped resources and conservative campaign reuse

Status: accepted. Date: 2026-10-24.

Use callback-scoped providers for consumer-owned values. Campaign, worker and
case scopes make lifetime explicit; reset external state before baseline and
candidate, acquire declared providers in order and release in reverse order.
Namespace environment additions and serialize only nonsecret identity/version/
epoch metadata. Default resource capacity to one. Acquire multi-resource claims
atomically within a finite campaign, preserving deterministic result order.
Separate Heni processes require external coordination.

Case-local evidence belongs to one worker; shared result updates are atomic and
journal writes/progress callbacks are serialized. Cancel and join every worker
before finalizing. Preserve original cancellation and all cleanup errors.
Fresh private workspaces remain the correctness reference.

Reuse only passing in-campaign baselines whose complete input contracts match.
Compare sensitive command/environment values in memory, without portable weak
hashes. Require nonsecret toolchain identity, exact structured producer identity
and known resource epochs; disable reuse for unidentified custom hooks. Record
baseline-owner provenance, never invent a fresh attempt artifact for a reused
baseline. No cross-run verdict cache is provided.

Incremental builds require an explicit Haskell provider that verifies content-key
observation before tests. Restore and inventory source independently, keep all
writable artifacts worker-private, and retire retained state after suspicious
source, reset, build observation or cleanup. Generic commands cannot prove a
universal invalidation rule, so no portable incremental-build flag is offered.
Same-size/coarse-mtime adversarial fixtures and fresh-mode parity are required
for a provider's claimed compatibility. Timings remain observations, while
isolation and invocation counts are correctness gates.
