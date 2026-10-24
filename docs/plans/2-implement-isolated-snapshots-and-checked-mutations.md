---
id: 2
slug: implement-isolated-snapshots-and-checked-mutations
title: "Implement isolated snapshots and checked mutations"
kind: exec-plan
created_at: 2026-10-24T14:33:08Z
intention: "intention_01m5q57803ea88q9ts1vv62h4r"
master_plan: "docs/masterplans/1-bootstrap-heni-for-trustworthy-mutation-testing-and-hackage-release.md"
provenance:
  created_by:
    model: "gpt-6-astra"
    harness: "codex-cli"
    at: 2026-10-24T14:33:08Z
  revisions:
    - model: "gpt-6.1-sol"
      harness: "codex-cli"
      at: 2026-10-24T15:07:55Z
      mode: "implement"
      note: "Implement immutable byte snapshots, checked staged edits, and scoped disposable workspaces"
---

# Implement isolated snapshots and checked mutations


This ExecPlan is a living document. Maintain Progress, Surprises & Discoveries, Decision Log, and Outcomes & Retrospective. Record implementation friction with `agents/skills/exec-plan/record-friction.ts` under this plan. Follow `agents/skills/exec-plan/ADR.md` before ADR changes, and distill durable decisions before completion. All commands below run from the repository root unless stated otherwise. Paths named as new files are planned artifacts, not claims that they already exist.


## Purpose / Big Picture


A caller can snapshot explicitly selected source contents, apply checked mutations in a disposable copy, and prove that the user's checkout stayed untouched. Missing anchors, partial patches, invalid UTF-8, and escaping paths become structured invalid mutations rather than misleading test results. This is independently demonstrable without a campaign runner.


## Progress


- [x] M1 (2026-10-24; deterministic SHA-256, dirty/untracked/binary capture and independent-copy checks pass): Snapshots preserve declared source bytes and isolate writable workspaces.
- [x] M2 (2026-10-24; checked replacement, create/delete, textual patches, unsafe-path and UTF-8 tests pass): Replacement, patch, and custom checked edits record exact changes and reject unsafe or invalid targets.
- [x] M3 (2026-10-24; partial-edit/patch rejection, reset-failure, cancellation and fresh-next-case checks pass): Failed edits and reset failures cannot contaminate another case or the active checkout.


## Surprises & Discoveries


Double capture and immutable in-memory bytes avoid exposing a mutable snapshot path. Memory scales with selected source bytes; this is documented rather than claiming a streaming implementation.


## Decision Log


2026-10-24: Use bracket-only workspace allocation/disposal so callers cannot construct arbitrary cleanup targets. The proposed standalone discardWorkspace is replaced by scoped withWorkspace. Textual Git patches use an injected bounded runner; EP-4 must wire the EP-3 supervisor.

2026-10-24: Reject source symlinks and special files, keep executable bits in identities, and publish staged edits only after a complete independent inventory. See [the snapshot ADR](../adr/3-immutable-snapshots-and-staged-edits.md).


## Outcomes & Retrospective


`cabal test heni:heni-workspace heni:heni-unit --test-show-details=direct` passes. Tests prove checkout preservation, binary/dirty/untracked capture, exact replacements, creation/deletion, UTF-8 rejection, symlink write/source rejection, no published partial candidate, stale multi-file patches, missing Git, cancellation and reset failure. Snapshot/edit boundaries are distilled in docs/adr/3-immutable-snapshots-and-staged-edits.md. FRIC-1 is accepted: the registered directory source was absent, so authoritative tagged upstream source was inspected. Linux execution remains a CI/release gate; this local run was macOS.


## Context and Orientation


At creation there is no implementation. Begin only when `docs/plans/1-establish-the-public-model-and-executable-api-contracts.md` is Complete: root `heni.cabal`, constrained paths/IDs, structured edit errors, and the classifier contract must exist. Read `docs/initial-spec.md` sections 5–6 and both records listed by `docs/research/index.md`. The local survey found repeated backup restoration over active checkouts; Heni eliminates that behavior by design.

A source snapshot is an immutable, content-identified copy of declared inputs. A workspace is a disposable mutable copy of that snapshot. A touched-file inventory records before/after bytes or digests, creation/deletion, and relevant mode changes. It is evidence of what actually changed, not just what an edit declared. Workspace isolation protects ordinary file operations; it is not a security sandbox for arbitrary consumer IO or subprocesses.

The prerequisite records [framework neutrality](../adr/1-framework-neutral-core.md) and [evidence-owned classification](../adr/2-evidence-owned-classification.md). This plan owns the separate durable decision on snapshot policy and edit confinement. Follow the core strict-record/explicit-deriving conventions without bringing orphan label instances into the library's import closure.


## Plan of Work


### M1: Immutable source identity and scoped copies


Implement `src/Test/Heni/Workspace.hs` and internal filesystem helpers, with `withSnapshot`, `withWorkspace`, `verifyWorkspace`, and `discardWorkspace` operations using the accepted model. Snapshot selected working-tree bytes, including dirty and explicitly included untracked files. Do not silently substitute Git HEAD. The default root policy includes regular files below the declared source root, excludes `.git`, run outputs, build directories, and known temporary artifacts, and records all defaults and user rules. Reject an output location that could recursively enter the snapshot; a nested explicitly excluded output is acceptable only after canonical containment validation. Offer explicit inclusion/exclusion policy rather than copying arbitrary machine directories.

Hash canonical relative names, contents, executable bits where relevant, and policy metadata in deterministic order. Verify a consistent capture by checking the selected inventory before/after copying and failing on detected concurrent changes; document that this is not an atomic filesystem snapshot under adversarial concurrent writers. The snapshot's own bytes are authoritative and immutable to later operations. Preserve binary files as bytes. Initially reject source symlinks rather than following them implicitly; document this first-release restriction with an actionable error. Reject sockets/devices and paths outside the root. Copy bytes into a unique private directory without hard-linking mutable files to the source or snapshot. The workspace and its build directory are exclusive to one worker.

### M2: Checked and atomic case edits


Implement `src/Test/Heni/Edit.hs` with ordered exact-count text replacement, file creation/deletion with explicit preconditions, patch application, and Haskell custom edits using a checked capability interface. Text replacements decode UTF-8 strictly, reject empty anchors, enforce a positive expected count defaulting to one, preserve bytes outside matched text, and reject a final no-change mutation. Later edits observe earlier edits. A sequence that cancels its own changes is invalid unless it is an explicit control. Controls require an unchanged final byte inventory.

Apply the entire edit sequence to a scratch candidate and publish it as the case workspace only after all preconditions and the final diff succeed. For patches, use Git as an explicitly optional runtime tool, check then apply inside a private staging tree, and discard any partial result. Accept a documented subset of textual patches first; reject binary patches and unsupported mode/symlink operations explicitly. Check every old and new path, creation/deletion target, and working directory. Reject absolute paths, parent traversal, NULs, and symlink components, including symlinks introduced during edits. Verify touched paths against actual inventory changes and disallow edits to runner-owned evidence/build metadata.

The custom hook API returns structured edit errors/evidence and uses checked read/write/create/delete operations. Recompute the final inventory independently; a hook's claimed list is not sufficient proof. Document that arbitrary Haskell IO can escape this capability by using other APIs and is trusted consumer code. Do not promise containment against hostile custom code or concurrent symlink attackers without an actual OS sandbox.

### M3: Isolation across failures


Add `test/workspace/` and the `heni-workspace` test target. Start with disposable per-case copies; expose reset/verification operations for later reuse without enabling reuse now. On failure, preserve error evidence outside the disposable tree, discard the candidate, and never copy a backup over the source root. A failed reset invalidates that worker and requires a fresh workspace. Exercise source deletion/creation, permission errors, cancellation while editing, failed cleanup, and a partial multi-edit sequence. Record snapshot policy and supported patch behavior in a local ADR and `docs/design/workspaces.md`.


## Concrete Steps


Locate filesystem/patch dependencies with Mori before using their APIs. Git is needed only for the patch test group; all other workspace tests must run without it.

```bash
mori registry search directory
mori registry search process
cabal test heni:heni-workspace --test-show-details=direct
cabal test heni:heni-unit --test-show-details=direct
```

Create fixture trees under test-managed temporary directories. The test target constructs its own Git patch fixtures rather than relying on the developer's Git status. Run the patch tests on Linux and macOS with Git installed, and a missing-Git test that requires a clear capability error rather than hanging or silently skipping a selected patch case.


## Validation and Acceptance


Verify a dirty file and an explicitly included untracked fixture are present in the snapshot and report identity; output/build files must be absent. A mutation cannot alter the original source or another workspace, verified by before/after hashes. Two matches fail the default one-match replacement. Invalid UTF-8 returns an edit error. The second edit failing leaves no published partial candidate. A patch with one good hunk and one stale hunk cannot contaminate the next case. A create/delete operation records the correct diff and preconditions. Traversal, absolute paths, source symlinks, and symlinks introduced by custom code are rejected before runner-owned mutation writes.

Repeated application always starts from the same snapshot and produces the same edited bytes or the same error. An explicit no-op control succeeds at the edit layer; an ordinary no-op fails. Reset failure is observable and prevents reuse. A normal permission/IO failure is infrastructure-error evidence, distinct from a stale patch or invalid anchor. Cleanup failure preserves evidence for the caller. Cancellation testing must use bounded watchdogs so regressions cannot hang CI.


## Idempotence and Recovery


Every test and operation uses a unique owned directory and records ownership before cleanup. Reruns allocate new directories; never delete a caller directory merely because its name resembles a workspace. Failed candidates are discarded or retained under an explicit diagnostic policy. Snapshot and source directories are never cleanup targets of a candidate reset. Preserve logs outside workspaces before removal.


## Interfaces and Dependencies


The hard prerequisite is `docs/plans/1-establish-the-public-model-and-executable-api-contracts.md`. This plan owns `SourceSnapshot`, `Workspace`, snapshot policy, edit application, and checked touched-file evidence under the agreed model. `docs/plans/4-run-baseline-to-report-mutation-campaigns.md` consumes them; `docs/plans/7-add-resource-aware-workers-and-verified-reuse.md` may later implement verified worker reuse.

`docs/plans/3-supervise-bounded-processes-and-cancellation.md` is an integration dependency for the Git subprocess, not a hard dependency for independent filesystem work. Use a bounded test helper until its supervisor exists; the campaign integration must route production Git checks/applications through that supervisor before acceptance. Do not duplicate process timeout or signal interpretation. Cryptographic identity dependencies must be looked up in Mori and checked against current Hackage/upstream releases before selection. No Git repository is required for non-patch operation.
