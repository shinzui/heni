---
type: Capability
title: "Required native property reproduction"
description: "Require a separate property replay to reproduce the original token, generator contract, and named failure set."
capabilityId: CAP-8
provider: mori://shinzui/heni
status: shipped
stability: experimental
since: unreleased
packages: ["heni", "heni-hspec"]
interface: ["Test.Heni.Hspec.heniProperty", "Test.Heni.Replay.replayCommand", "CaseHooks.replayBuilder", "replayRequired"]
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
requires: ["CAP-7"]
evidence:
  - kind: test
    resource: test/adapter/Main.hs
    proves: "Runs required replay, changed-token rejection, and replay-timeout rejection with retained stages."
  - kind: test
    resource: adapters/heni-hspec/test/Main.hs
    proves: "Exercises native QuickCheck evidence and replay behavior."
  - kind: example
    resource: examples/adapters/property.json
    proves: "Requires replay of the selected suite/property failure."
  - kind: guide
    resource: docs/user/adapters.md
    proves: "Defines tokens, generator identity, reproduction requirements, and the one-property boundary."
---

# Required native property reproduction

The Hspec helper records QuickCheck seed/size, version, generator arguments,
and counterexample for one selected property. Required replay uses a separate
supervised Replay stage in the edited workspace and must reproduce the original
contract and exact named failure set. A missing/malformed token, mismatch, or
replay timeout is rejected while retaining original and replay observations.

The initial helper supports one selected replay property per attempt. Other
native frameworks require consumer-owned typed replay builders and compatible
protocol production; there is no universal seed language. Counterexamples can
contain sensitive application data, which the consumer must handle before export.

Builds on [named assertion evidence](named-test-reporters.md) (CAP-7).
Use the property fixture in the [reporter guide](../user/named-test-guide.md).
