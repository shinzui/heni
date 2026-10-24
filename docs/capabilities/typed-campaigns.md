---
type: Capability
title: "Typed Haskell mutation campaigns"
description: "Construct validated typed campaigns and execute a complete baseline-to-result lifecycle through the core library."
capabilityId: CAP-1
provider: mori://shinzui/heni
status: shipped
stability: experimental
since: unreleased
packages: ["heni"]
interface: ["Test.Heni.mkCampaign", "Test.Heni.runCampaign", "Test.Heni.defaultRunOptions"]
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
evidence:
  - kind: module
    resource: src/Test/Heni/Runner.hs
    proves: "Validates definitions and runs the shared baseline, candidate, classification, and report lifecycle."
  - kind: test
    resource: test/runner/Main.hs
    proves: "Exercises real Cabal caught, survived, and unrelated build failure cases, baseline refusal, and lifecycle failures."
  - kind: example
    resource: examples/library/Definitions.hs
    proves: "Defines runnable typed mutation cases without a manifest or CLI dependency."
  - kind: guide
    resource: docs/user/haskell-integration.md
    proves: "Shows campaign construction, explicit options, and caller-owned result handling."
---

# Typed Haskell mutation campaigns

Use the core `heni` package to define commands, checked edits, and exact
expectations in Haskell. `mkCampaign` validates command references and hook
registrations before `runCampaign` executes the selected cases. Start with
`defaultRunOptions` and update named fields. The library returns `RunResult`;
the embedding application owns rendering and process exits.

The core's public API exposes no Tasty or Hspec test types. It accepts trusted
custom edit and evidence hooks separately from serializable case definitions.
Those hooks must cooperate with cancellation; arbitrary IO is not sandboxed.
Embedding executables enable the threaded runtime. Available in the default
branch's unreleased 0.1.0.0 packages.

Follow the [Haskell guide](../user/haskell-integration.md), then consult the
[API reference](../user/api-contract.md). The independent
[consumer](../../examples/standalone/Main.hs) demonstrates package consumption.
