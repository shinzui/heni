---
type: Capability
title: "Verified private incremental build reuse"
description: "Retain private worker build artifacts only under a Haskell provider that verifies the build observed the exact staged input identity."
capabilityId: CAP-12
provider: mori://shinzui/heni
status: shipped
stability: experimental
since: unreleased
packages: ["heni"]
interface: ["Test.Heni.BuildReuse.BuildReuse", "RunOptions.buildReuse", "HENI_BUILD_INPUT_ID"]
tags: ["mutation-testing", "haskell"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T23:16:53Z
reviews:
  - kind: model
    reviewer: codex/gpt-6
    reviewed_at: 2026-10-24T23:16:53Z
    document_timestamp: 2026-10-24T23:16:53Z
    scope: content-and-metadata
    outcome: commented
    provider: openai
    model: gpt-6
    effort: unspecified
    context: >-
      Author self-review against the listed local source, test definitions, and
      examples, including evidence-path and dependency-link checks. Availability
      means implemented on the default branch, not a Hackage release. No
      independent approval or new execution of every cited test is claimed.
requires: ["CAP-1", "CAP-2"]
evidence:
  - kind: module
    resource: src/Test/Heni/BuildReuse.hs
    proves: "Restores and verifies staged source, retains approved private artifact directories, and requires build observation."
  - kind: test
    resource: test/scheduler/Main.hs
    proves: "Exercises same-size equal-mtime edits, fresh/retained parity, stale observation rejection, and retiring invalid trees."
  - kind: guide
    resource: docs/user/scheduling.md
    proves: "Describes verifier obligations, permitted directories, invalidation, and lack of a universal cache switch."
  - kind: guide
    resource: docs/user/build-reuse-guide.md
    proves: Worked Haskell adoption with compiled example source.
  - kind: example
    resource: examples/haskell-guides/GuideBuild.hs
    proves: Runnable public-API recipe with checked expected outcomes.
---

# Verified private incremental build reuse

Supply a trusted Haskell `BuildReuse` provider declaring retained build
directories, a build-tool contract, optional input preparation, and a verifier for
`HENI_BUILD_INPUT_ID`. Heni restores exact staged source and verifies source
inventories before/after use. Tests and expected compiler rejection require a
successful observation check.

Only `dist`, `dist-newstyle`, and `.heni-build` may be retained. Command/environment
changes reset artifacts; failed observation/reset or unexpected generated inputs
invalidate the case and retire the tree. Each worker owns its retained tree.
The consumer verifier is trusted integration, not attestation. Generic portable
commands have no universal timestamp/invalidation guarantee, so this provider is
Haskell-only and cannot be enabled through a generic manifest flag.

Builds on [typed campaigns](typed-campaigns.md) (CAP-1) and
[checked workspaces](isolated-checked-edits.md) (CAP-2). It can be adopted without
baseline sharing. Read the [reuse contract](../user/scheduling.md) and compare
retained execution against fresh results before adopting it.

See the [worked Haskell guide](../user/build-reuse-guide.md) and its compiled example.
