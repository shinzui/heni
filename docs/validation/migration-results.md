# Representative migration evidence

Accepted local trials on 2026-10-24 used Apple M1 Max/aarch64 macOS,
GHC 9.12.4 and Cabal 3.16.1.0, with a warm installed dependency cache and fresh
case workspaces. All four independently authored families ran through public
Haskell definitions and CLI manifests. The generated Haskell case used a custom
checked transformation; its manifest equivalent used replacement. No surveyed
consumer repository or service was modified or executed.

Reproduce with `sh scripts/test-migrations.sh`. The script explicitly enables
cross-package tests and supplies a separately built CLI. It retains reports and
logs under `.heni-runs/heni-migration-*`, including failed attempts. Condensed
observations are in [migration-measurements.json](migration-measurements.json);
[source identities](migration-source-identities.json) distinguish the refreshed
files from the historical RES-1 snapshots. The current rdkafka runner is 453
lines; the historical research described a different 349-line revision.

Every family produced Caught and Survived with matching typed/CLI meaning and
identical source snapshot identities. Replacement additionally produced
UnexpectedBuildFailure for an unrelated compiler error, and Caught only when
that rejection was explicitly declared with its compiler diagnostic. The
exit-only comparison actually accepted the unrelated compiler failure, proving
the attribution improvement. The external checker also rejected a timeout-rule
error as WrongFailure when the case required a capacity-rule diagnostic.

The combined trial matched wrong named assertion, known zero selection, stale
edit, test hang, failed setup, broken teardown, replay, fresh native crash and
unchanged control outcomes. Reports with a stale schema were rejected. The
real native QuickCheck counterexample integration remains in the optional
Hspec package's accepted test, while the combined core trial exercises its
framework-neutral replay channel. All selected IDs were accounted for. The
process and scheduler suites separately prove cancellation, worker isolation,
resource capacities, cleanup and post-teardown final progress events.

An initial combined run conservatively reported infrastructure failure during a
serial timeout. Failure retention was corrected, and subsequent regressions
identified a macOS group-exit race: killpg briefly returned EPERM before ESRCH.
An independent 100-iteration probe reproduced the transition. The supervisor
now polls within its existing shutdown bounds and clears provisional errors
only after definite disappearance; persistent errors still invalidate evidence.
The focused process suite includes twelve short-timeout repetitions, and the
adapter suite verifies retained replay-timeout evidence. The accepted full
migration run and its retained artifacts remain valid; no failed timeout was
counted as detection.

The following counts describe only the independently authored comparison
harness, not removable code in production projects. A further 17 shared
nonblank/noncomment lines implement copying, scoped disposal and command
capture. Per-family orchestration counts exclude the two definition lines and
include the local wrapper. Manifest consumers add zero lifecycle-scaffolding
lines; command configuration, edits and witnesses remain necessary data.
Generator/checker build helpers remain consumer-owned in both paths.

| Family | Comparison orchestration LOC | Definition LOC | Retained domain/build helper LOC | Typed fresh seconds | CLI parallel/reuse seconds | Baseline builds, fresh / reuse |
| --- | --- | --- | --- | --- | --- | --- |
| replacement | 4 | 2 | 0 | 100.067 | 47.106 | 4 / 2 |
| patch-catalogue | 4 | 2 | 0 | 59.413 | 30.661 | 2 / 1 |
| generated-code | 5 | 2 | 16 | 62.961 | 31.537 | 2 / 1 |
| diagnostic-checker | 4 | 2 | 22 | 4.973 | 2.729 | 2 / 1 |

The library conditions use one worker and fresh baselines; CLI conditions use
two workers and compatible baseline sharing. They preserve meaning but combine
multiple performance changes. There is one accepted whole-campaign timing per
condition, so whole-campaign variance is not estimated. Unchanged baseline
builds repeat within the fresh campaigns; their ranges and the sum of build
stage times are recorded in the JSON. The controlled Cabal workload in
[the scheduling evidence](../design/scheduling.md) has two repeats per condition
and reports its variation independently. These data do not predict universal
speedups.

Fresh library elapsed time minus the sum of supervised stage durations was
0.019–0.083s across these tiny fixtures. This difference includes source copies,
checks, custom edits, reporting IO and timing granularity; it is not isolated
runner CPU time. Build/test work dominates these examples, while stronger
failure attribution is independently observable.

An automated template-addition trial changed three case fields (ID, description
and edits), serialized one manifest and ran one `check` command. Each family
was repeated three times; `check` confirmed it executed no tests. The figures
below measure automation plus process/static-check latency, excluding human
fault selection or reasoning.

| Family | Median automated addition/check ms | Range ms |
| --- | --- | --- |
| replacement | 25.42 | 25.29–58.23 |
| patch-catalogue | 389.22 | 373.92–407.45 |
| generated-code | 24.49 | 24.13–24.87 |
| diagnostic-checker | 24.00 | 23.51–24.65 |

Diagnosis required two artifact reads: report expectation/actual IDs and the
dedicated test protocol. It identified expected `suite/intended` versus actual
`suite/other`. Five automated reads took a median of
0.655ms; no human diagnosis
time is inferred. One CLI command reproduced the checker Caught result with
exit 0 in 2.589s.

To repeat the observations after a complete trial:

```bash
python3 scripts/measure-migration.py --results .heni-runs/migration-results.json --cli /path/from/cabal-list-bin/heni --output docs/validation/migration-measurements.json
```

The API review found concrete case data, checked custom transformations,
framework-neutral evidence, explicit resource scopes and redacted reports
sufficient for these four families. It exposed and fixed workspace-built
executable preflight and post-teardown progress ordering. It did not establish
support for binary mutation, arbitrary generated-output ordering, all property
frameworks, database-state rollback or unverified incremental build tools.
Those limits and later consumer migration batches are explicit in
[the guide](../migration-guide.md). No human usability study, fleet migration,
Hackage candidate review or publication is claimed.
