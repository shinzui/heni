# Migration proof and consumer-owned fault meaning

Status: accepted. Date: 2026-10-24.

Heni owns disposable source lifecycles, supervision, baseline validity,
attribution and reports. Consumers retain fault meaning, selected assertions,
generator/checker code and external resource reset semantics. Representative
fixtures are independently authored and redistributable; do not copy or silently
migrate the surveyed repositories as part of validating this boundary.

For generated code, mutate generator input before generation when possible.
An output mutation requires a consumer workflow that preserves and verifies the
artifact through compilation. Do not hide a regenerating build behind a claim
that the original edit reached the test. Workspace-built ./program executables
resolve after build inside the checked stage cwd.

A portable manifest is sufficient for common edits and exact diagnostics.
Haskell-only transformations and verifiers remain explicit trusted callbacks;
no second general-purpose runner belongs in migration examples. Strong named
protocols retain their exact identities instead of falling back to terminal
scraping. Database-state fault injection and live-service acceptance remain
consumer work beyond filesystem isolation.

The cross-package migration trial is an explicit integration gate with a
separately built CLI executable. Keep it out of default core test dependencies
to preserve independent core archives and avoid Cabal build-tool cycles. Release
CI must run the integration gate and optional reporter tests.

Measure fixture lifecycle scaffolding separately from mutation definitions,
domain/build helpers, automated interface actions and compiler time. Agent-run
observations do not establish human usability or production-wide savings.
Historical survey evidence, refreshed source identities and newly executed
trials are separate claims. No migration or publication is implied by local
parity evidence.
