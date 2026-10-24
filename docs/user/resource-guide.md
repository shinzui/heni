---
type: Guide
title: "Configure workers and consumer resources"
description: "Introduce bounded concurrency and scoped fixtures, then opt into reuse only with complete identities."
docId: DOC-17
tags: ["workers", "resources", "baselines", "reuse"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:57:52Z
sources:
  - resource: src/Test/Heni/Resource.hs
  - resource: test/scheduler/Main.hs
  - resource: schemas/manifest-v1.schema.json
---

# Configure workers and consumer resources

Start with serial fresh-copy execution and a passing single case. Before adding
workers, choose a safe total budget: worker count times each build's job count,
plus fixture capacity. For the minimal independent fixture, this runs two cases
with two workers and per-build Cabal `-j1`:

```sh
cabal run heni-cli:exe:heni -- run examples/minimal/heni.json --case guard-bypass --case survivor --jobs 2 --output .heni-runs/two-workers
```

Expect exit 1 because the selected survivor remains a failure of the campaign's
contract. Final results retain author order even when completion order differs.
Workers accept 1–256; CLI `--jobs` overrides manifest `execution.workers`.

For an external service, implement bounded prepare, reset, and release commands
in the consumer project. Test them directly before adding a manifest resource.
The following root-field fragment refers to command IDs you must define:

```json
{
  "execution": {"workers": 2},
  "resources": [{
    "name": "DB", "scope": "case", "capacity": 1,
    "identity": "integration-db", "version": "fixture-v1", "epoch": "clean-v1",
    "environment": {"HENI_RESOURCE_DB_PORT": "consumer-allocated-port"},
    "setup": "prepare-db", "reset": "reset-db", "teardown": "release-db"
  }]
}
```

Add `"resources": ["DB"]` to each case that needs the fixture. Resource names use
uppercase ASCII, digits, and underscores; environment bindings for DB begin
`HENI_RESOURCE_DB_`. Replace placeholders with actual allocated bindings and
meaningful state identities. Reset must restore equivalent state before both
baseline and candidate. Teardown must release acquired state; setup must clean
up its own partial effects when it fails. Source workspace removal does not
roll back a database.

Keep capacity one until simultaneous use/reset has been established. Choose case,
worker, or campaign scope according to fixture lifetime. Locks and capacities
coordinate one Heni process; separate campaigns need separate namespaces or an
external lock. Inspect resource lifecycle records and both primary and teardown
errors when a run is untrustworthy.

Only then consider baseline reuse. Set root
`execution.baselineReuse.toolchain` to a nonsecret identity for your complete
compiler/dependency/build contract. Structured suites additionally identify their
exact producer as `execution.baselineReuse.adapter`. Heni compares inputs,
commands, selectors, expectations, environment, and resource identity/version/epoch.
Do not invent an epoch for unknown service state. Sharing is campaign-local and
requires passing compatible baselines; no previous campaign verdict is trusted.

Retaining incremental build artifacts is a separate Haskell integration. Supply
`BuildReuse` only when your verifier can prove the build observed
`HENI_BUILD_INPUT_ID`; compare results with fresh execution. There is no generic
manifest switch for that proof. The [scheduling reference](scheduling.md) explains
invalidation, cancellation, callback obligations, and measured fixture limits.
