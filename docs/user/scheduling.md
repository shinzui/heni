---
type: Reference
title: "Resources, workers and conservative reuse"
description: "Look up worker limits, scoped resources, baseline sharing, and verified build reuse."
docId: DOC-12
tags: ["workers", "resources", "reuse"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:57:52Z
sources:
  - resource: src/Test/Heni/Runner.hs
  - resource: test/scheduler/Main.hs
---

# Resources, workers and conservative reuse

The [Haskell build reuse guide](build-reuse-guide.md) implements a content-aware GHC
wrapper, a matching observation verifier, fresh parity, and stale-receipt refusal.

Fresh execution is the reference mode. `RunOptions.workers` defaults to one and
accepts 1–256; CLI `--jobs N` overrides `execution.workers`. Each case gets fresh
baseline/candidate copies unless a Haskell build provider explicitly opts in.
Selection and final report order remain author order, even when independent
cases complete in another order. Journal writes and progress callbacks have one
owner; case evidence is private to its scheduled worker.

Resource names use uppercase ASCII with digits/underscores. Providers choose
campaign, worker or case scope. `managedResource` brackets a consumer value,
returns nonsecret identity/version/epoch plus namespaced environment additions,
and resets before both baseline and candidate. Acquisitions compose in declared
order and release in reverse order, including partial acquisition failure.
Primary and teardown errors are both preserved. A failed resource operation is
infrastructure evidence. Trusted Haskell callbacks must make their own foreign
calls interruptible; Heni cannot promise a deadline for uninterruptible code.

Portable resources use named setup/reset/teardown commands, each with its own
budget and output limit, in a private resource workspace. Example root fields:

```json
{
  "execution": {"workers": 2},
  "resources": [{
    "name": "DB", "scope": "case", "capacity": 1,
    "identity": "local-fixture", "version": "v1", "epoch": "clean",
    "environment": {"HENI_RESOURCE_DB_PORT": "allocated-by-consumer"},
    "setup": "prepare-db", "reset": "reset-db", "teardown": "release-db"
  }]
}
```

Only resources claimed by selected cases are acquired. Each case declares
`resources: ["DB"]`; commands reference ordinary manifest
command definitions. Environment names must start `HENI_RESOURCE_DB_` for this
resource and values are redacted. The consumer supplies actual allocated ports
or paths, reset/teardown semantics and meaningful epochs. An absent epoch is
honest unknown state. A failed acquire must clean up its own partial effects;
Heni releases earlier successfully acquired providers. Workspace deletion does
not roll back a service.

Multiple claims are acquired atomically against campaign-wide capacities, so
opposite declaration orders cannot deadlock. Capacity defaults to one. Worker-scoped capacities also bound the worker pool,
so acquiring idle worker fixtures cannot exceed the declared budget. Higher
capacity is an explicit consumer assertion that simultaneous use/reset is safe.
Finite queued work can pass blocked items to run independent cases; blocked
items become eligible when owners release capacity. Cancellation stops the
queue, terminates owned commands, joins workers, releases providers and
finalizes selected IDs once. These limits coordinate one Heni process only;
independent processes need external locks or separate fixture namespaces.

`execution.baselineReuse: {"toolchain":"ghc/dependency/build-contract"}` opts
into campaign-local baseline sharing. Haskell uses `ReuseBaselines` with the
same nonsecret contract. The key compares snapshot bytes/policy, build/test
commands and arguments, environment overrides and inherited values, selector,
expectation/evidence mode, resource identity/version/epoch and toolchain
contract. Secrets are compared in memory, never exported or weakly hashed.
Structured suites additionally declare the exact producer string as `adapter`;
it must agree with the observed producer. Unknown resource epochs or custom
hooks without identities disable sharing. A consumer opting in asserts that
external inputs are represented and tests do not depend semantically on fresh
run/case/attempt IDs. Reports record owner-case provenance and reasons.

Only passing baselines are shared. One producer serves matching waiters;
cancellation wakes them without publishing success. Failure/cleanup errors
invalidate the cache. A new campaign has no trusted prior verdicts. Resource
identity/epoch/environment must agree between a case's baseline and candidate.
This is deliberately more conservative than caching only source filenames.

Incremental build artifacts require the Haskell-only `BuildReuse` provider.
It declares a build-tool contract, retained `dist`, `dist-newstyle` or
`.heni-build` directories, optional input preparation and a verifier that the
build observed `HENI_BUILD_INPUT_ID`. Each worker owns its own retained tree.
Heni restores exact staged source bytes, verifies source independently before
and after commands, and checks the build observation before tests or accepting an expected compiler
rejection. Command or
environment changes discard retained artifacts. Failed reset, unexpected
generated inputs or an invalid observation retires the tree; its next use starts
with all artifacts removed. Generic commands have no automatic timestamp or
invalidation guarantee, so this provider cannot be serialized as a universal
manifest option. The verifier is trusted consumer integration, not attestation.

`test/scheduler/Main.hs` proves same-size alternating edits with all input mtimes
set to the same epoch. Fresh and retained builds agree; a deliberately stale
build fails observation validation, and the following case starts fresh. It
also proves baseline invocation counts, selector/command/epoch/environment
invalidation, isolated writes, opposite-order claims and cancellation cleanup.

The real Cabal workload is `heni-campaign-bench`, using three fixture cases.
Run fresh and reuse modes repeatedly and compare baseline invocations, wall
time, the sum of build-stage durations, and peak case concurrency separately.
Build-stage time includes Cabal/compiler orchestration; it is not compiler CPU
time. Timing is observational, never a correctness threshold. Each example
uses Cabal `-j1`: budget total build jobs as mutation workers times per-build
jobs, plus declared fixture capacity. Increasing workers does not imply a
universal speedup. Measurements for this checkout follow.


On 2026-10-24, Apple M1 Max/aarch64 macOS, GHC 9.12.4, Cabal 3.16.1.0:

| Mode | Repeat | Workers | Baseline builds | Wall seconds | Sum build-stage seconds | Peak cases |
| --- | --- | --- | --- | --- | --- | --- |
| fresh | 1 | 1 | 3 | 81.118 | 52.079 | 1 |
| fresh | 2 | 1 | 3 | 81.132 | 51.864 | 1 |
| reuse | 1 | 2 | 1 | 37.707 | 35.152 | 2 |
| reuse | 2 | 2 | 1 | 37.896 | 35.196 | 2 |

Fresh wall-time range was 81.118–81.132s; reuse/two-worker range was
37.707–37.896s. Each run used a new source snapshot/private workspace with the
same warm installed dependency cache. These figures combine baseline sharing
and parallelism, so they do not isolate either effect. Both modes preserved
Caught/Survived/UnexpectedBuildFailure outcomes. Correctness is established by
fresh parity and 3→1 baseline counts, not by these timing differences. The sum
of stage times is work across processes and can exceed wall time when tasks
overlap. This small fixture does not predict consumer-project speedups.
