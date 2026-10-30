---
type: Improvement Request
title: Reuse one incremental Cabal build per worker across baselines and candidates
description: >-
  A campaign over a large Cabal project pays a cold build for every distinct baseline, because
  baselines always run in a fresh workspace and the baseline key includes the case selector.
  Build the unchanged source once per worker in its retained build directory, run each
  selector's baseline tests against that build, and ship a Cabal build-reuse provider so a
  manifest can opt in.
generated:
  by: claude-code/claude-opus-5-5
  at: 2026-10-30T13:06:50Z
requestId: IR-1
status: proposed
origin: mori://shinzui/nagare
---

# Improvement Request: Reuse One Incremental Cabal Build per Worker

## Status

Proposed by [Nagare](mori://shinzui/nagare) while assessing whether Heni could replace its
mutation sweep. Not a dependency: Nagare keeps its own sweep until Heni can run the same
catalogue at comparable cost.

## Context

Nagare's catalogue has 189 records (188 `test-fails`, one `build-fails`) using 150 distinct test
patterns (`cli/nagarectl/test/mutations/records.json` under `mori://shinzui/nagare`; the
artifact-level URI is pending). Its sweep (`nix/test-runs.nix`, `mutationSweep` and
`sweepWorker`, under `mori://shinzui/nagare` at `91d54e06a4d1696f01adfe10b2046736a49e0611`)
runs four workers. Each builds the revision once with Cabal at `-O0`, then per record patches,
rebuilds incrementally, runs the record's pattern and reverses the patch. The suite is never
built cold more than four times per sweep.

Heni at `81696f8a2b1263312497e703bae7ac7f2139cd8b` would build that catalogue cold about 150
times:

1. `executeBaseline` in `src/Test/Heni/Runner.hs` runs every baseline inside
   `withWorkspace snapshot`, a fresh copy with no build directory. `BuildReuse` applies only to
   candidates.
2. `BaselineKey` includes the case `selector`, so `ReuseBaselines` shares a baseline only
   between cases with the same pattern. With 150 patterns, 150 baselines build from scratch.
3. `BuildReuse` is Haskell-only. A manifest user cannot reach it, and Heni ships no provider
   for Cabal, so each consumer would write its own wrapper and verifier.
4. `withBuildCandidate` in `src/Test/Heni/BuildReuse.hs` removes and rewrites every
   non-retained file before each candidate and inventories the whole tree four times. Cabal's
   file monitor falls back to hashing and GHC 9.4+ recompiles by source hash, so this should
   not cause a rebuild, but it adds whole-tree I/O per case. Its cost on a large tree is
   unmeasured.

## Requested Change

1. **Split the baseline into a build and a per-selector test run.** Build the unchanged
   snapshot once per worker, in that worker's retained build directory, under the same build
   contract as candidates. Run each case's baseline test command against that build, keyed by
   selector as today. A failed or unverifiable baseline build retires the worker, as a failed
   candidate already does.
2. **Ship a Cabal build-reuse provider** reachable from the manifest, for example
   `execution.buildReuse: {"provider": "cabal", "toolchain": "..."}`. The wrapper runs the
   declared build command and, only on success, writes a receipt holding `HENI_BUILD_INPUT_ID`
   into `.heni-build/`. The verifier checks that receipt before tests run.
3. **Restore only changed inputs between candidates.** Compare the previous candidate's
   inventory with the staged one and rewrite only the differing files, keeping the
   unexpected-state checks.

## Design question for Heni

The current contract asks the verifier to prove the build *observed* the staged inputs. A Cabal
receipt proves the build ran to completion on those inputs. Whether its output is correct
relies on Cabal's incremental invalidation, the same trust Nagare's sweep places today. Heni
should decide whether to accept this as a declared trusted-tool contract, recorded as such in
the report, with fresh execution remaining the reference mode for parity checks.

## Acceptance

- A campaign of N cases on W workers over a Cabal project performs at most W cold builds,
  shown by build logs or stage timings in the report.
- Fresh and reused execution produce the same verdict for every case of a representative
  campaign, including a survivor, a compile-rejected mutation and a stale edit.
- A stale or missing receipt fails the case as an infrastructure error before tests run, never
  as a kill.
