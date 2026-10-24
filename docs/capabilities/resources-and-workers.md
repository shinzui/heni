---
type: Capability
title: "Scoped resources and bounded parallel cases"
description: "Schedule private case workspaces under worker and resource capacities with consumer-owned acquire, reset, and release semantics."
capabilityId: CAP-10
provider: mori://shinzui/heni
status: shipped
stability: experimental
since: unreleased
packages: ["heni"]
interface: ["RunOptions.workers", "Test.Heni.Resource.managedResource", "RunOptions.resources", "RunOptions.resourceClaims", "execution.workers"]
tags: ["mutation-testing", "haskell"]
generated:
  by: codex/gpt-6
  at: 2026-10-24T22:59:21Z
reviews:
  - kind: model
    reviewer: codex/gpt-6
    reviewed_at: 2026-10-24T23:01:10Z
    document_timestamp: 2026-10-24T22:59:21Z
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
requires: ["CAP-1"]
evidence:
  - kind: test
    resource: test/scheduler/Main.hs
    proves: "Exercises all resource scopes, atomic claims, bounded acquisition, private trees, failure evidence, and cancellation release."
  - kind: module
    resource: src/Test/Heni/Resource.hs
    proves: "Provides typed campaign/worker/case resource lifecycle and binding contracts."
  - kind: example
    resource: heni-cli/test/corpus/valid-resources.json
    proves: "Shows declarative resources, namespaced bindings, and case claims."
  - kind: guide
    resource: docs/user/resource-guide.md
    proves: "Explains budgeting, portable setup/reset/teardown, scopes, and external ownership."
---

# Scoped resources and bounded parallel cases

Choose 1–256 workers while retaining private evidence/workspaces and final
author order. Campaign-, worker-, or case-scoped providers supply nonsecret
identity/version/epoch and namespaced environment bindings. Portable manifests
use explicit setup/reset/teardown commands. Multiple resource claims are admitted
atomically within campaign capacities.

Reset happens before baseline and candidate; releases run in reverse order and
preserve teardown errors. Consumers own service allocation and partial-acquire
cleanup. Capacity greater than one asserts concurrent use/reset is safe.
Independent Heni processes need external locking or separate namespaces. Filesystem
cleanup does not roll back service state, and arbitrary Haskell callbacks must
make their own foreign calls interruptible.

Builds on [typed campaigns](typed-campaigns.md) (CAP-1).
Use the [resource guide](../user/resource-guide.md) and
[scheduling reference](../user/scheduling.md).
